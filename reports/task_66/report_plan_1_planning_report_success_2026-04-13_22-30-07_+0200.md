# Connectivity API for zenoh-kotlin — Final Implementation Plan

## Context

The upstream zenoh Rust library added an unstable connectivity API (in `zenoh/src/api/info.rs`,
`zenoh/src/api/builders/info_transport.rs`, `zenoh/src/api/builders/info_links.rs`) that exposes
network-level introspection: snapshot queries for active transports/links, and listener subscriptions
for transport/link lifecycle events. The Go binding implements this in PR #17. This task brings the
same API to zenoh-kotlin via JNI.

**History of plan revisions:** Four prior plans were rejected. The last two failed because:
1. Prior plan (ctx_rec_5) used raw `Arc::into_raw` transport pointer round-trip to solve the
   "multiple transports to same peer" identity problem — but Go/upstream use snapshot-by-value with
   `Transport::new_from_fields` reconstruction. Hidden JNI pointers inside a pure snapshot class
   breaks the API contract: transports from events (which have no JNI pointer) couldn't be used
   as filters, and there was no lifecycle/cleanup defined for them.
2. `isShm` was included without the `shared-memory` Cargo feature being enabled.

**Correct transport filter approach:** Transport is a pure Kotlin data class. When a transport filter
is needed in JNI, the Rust side reconstructs the `Transport` value using
`Transport::new_from_fields(zid, whatami, is_qos, is_multicast)` — this is safe because:
- `internal` feature IS enabled on the zenoh dep (exposes `new_from_fields`)
- `#[cfg(feature = "shared-memory")]` makes `is_shm` disappear from the signature when that
  feature is absent (which it is here)
- Upstream `get_links`/`link_events_listener` filter by field equality, not pointer identity

---

## Closest Analog

`AdvancedSubscriber.declareSampleMissListener` + `SampleMissCallback`/`SampleMissHandler<R>`/
`SampleMissChannelHandler` + `SampleMissListener` + `JNISampleMissListener` —
dedicated callback/handler/channel types, 6 overloads (3 foreground + 3 background), `@Unstable`,
delegated through JNISession → Session → SessionInfo.

**Key difference from SampleMiss:** connectivity listeners are session-level (declared on
`SessionInfo`, not `AdvancedSubscriber`), so they must be added to `Session.strongDeclarations`
upon declaration (same category as Subscribers/Queryables).

---

## Upstream Rust API (all `#[zenoh_macros::unstable]`)

- `session.info().transports().wait()` → `Box<dyn Iterator<Item=Transport>>`
- `session.info().links()` → `LinksBuilder` → `.transport(t)` (optional) → `.wait()` → `Box<dyn Iterator<Item=Link>>`
- `session.info().transport_events_listener()` → builder → `.history(bool)` → `.callback(f)` / `.background()` → `.wait()`
- `session.info().link_events_listener()` → builder → `.history(bool)` → `.transport(t)` (optional) → `.callback(f)` / `.background()` → `.wait()`

**Transport fields (no `is_shm` — shared-memory feature absent):**
`zid: ZenohId`, `whatami: WhatAmI`, `is_qos: bool`, `is_multicast: bool`

**Link fields:**
`zid: ZenohId`, `src: Locator`, `dst: Locator`, `group: Option<Locator>`, `mtu: u16`,
`is_streamed: bool`, `interfaces: Vec<String>`, `auth_identifier: Option<String>`,
`priorities: Option<(u8,u8)>`, `reliability: Option<Reliability>`

**`Transport::new_from_fields` (via `internal` feature, without `shared-memory`):**
`new_from_fields(zid, whatami, is_qos, is_multicast) -> Transport`

---

## Implementation Plan

### 1. New data types — `io.zenoh.connectivity` package

All annotated `@Unstable`.

- **`Transport.kt`** — `data class`: `zid: ZenohId`, `whatAmI: WhatAmI`, `isQos: Boolean`,
  `isMulticast: Boolean`. Pure snapshot, no JNI pointers, `copy()`-safe.
- **`Link.kt`** — `data class`: `zid: ZenohId`, `src: String`, `dst: String`, `group: String?`,
  `mtu: Int`, `isStreamed: Boolean`, `interfaces: List<String>`, `authIdentifier: String?`,
  `priorityMin: Int?`, `priorityMax: Int?`, `reliability: Reliability?`
  (reuse `io.zenoh.qos.Reliability`)
- **`TransportEvent.kt`** — `data class`: `kind: SampleKind`, `transport: Transport`
- **`LinkEvent.kt`** — `data class`: `kind: SampleKind`, `link: Link`
- **`TransportEventsListener.kt`** — class implementing `SessionDeclaration + AutoCloseable`,
  wrapping `JNITransportEventsListener?`; same undeclare/close/finalize pattern as
  `SampleMissListener.kt`
- **`LinkEventsListener.kt`** — same pattern wrapping `JNILinkEventsListener?`

### 2. Callback/Handler types — `io.zenoh.handlers` package

Follow `SampleMissCallback` / `SampleMissHandler<R>` / `SampleMissChannelHandler` exactly:

- `TransportEventsCallback` — `@Unstable fun interface { fun run(event: TransportEvent) }`
- `TransportEventsHandler<R>` — `@Unstable interface` with `handle(event)`, `receiver(): R`, `onClose()`
- `TransportEventsChannelHandler` — internal class wrapping `Channel<TransportEvent>`
- `LinkEventsCallback`, `LinkEventsHandler<R>`, `LinkEventsChannelHandler` — same for `LinkEvent`

### 3. JNI callback interfaces — `io.zenoh.jni.callbacks` package

**`JNITransportEventsCallback`:**
```
fun run(kind: Int, zidBytes: ByteArray, whatAmI: Int, isQos: Boolean, isMulticast: Boolean)
```

**`JNILinkEventsCallback`:**
```
fun run(kind: Int, zidBytes: ByteArray, src: String, dst: String, group: String?,
        mtu: Int, isStreamed: Boolean, interfaces: Array<String>,
        authIdentifier: String?, priorityMin: Int, priorityMax: Int, reliability: Int)
```
- `interfaces` → proper Java `String[]` (not delimiter-joined)
- `priorityMin`, `priorityMax`, `reliability` → `-1` sentinel for `None`

### 4. JNI listener wrappers — `io.zenoh.jni` package

- **`JNITransportEventsListener.kt`** — holds `ptr: Long`; `close()` calls `freePtrViaJNI(ptr)`.
  Same as `JNISampleMissListener.kt`.
- **`JNILinkEventsListener.kt`** — same pattern.

### 5. Extend `JNISession.kt`

**External declarations:**

```kotlin
private external fun getTransportsViaJNI(ptr: Long): List<Any>
private external fun getLinksViaJNI(
    ptr: Long,
    transportZid: ByteArray?, transportWhatAmI: Int, transportIsQos: Boolean, transportIsMulticast: Boolean
): List<Any>
private external fun declareTransportEventsListenerViaJNI(
    ptr: Long, callback: JNITransportEventsCallback, onClose: JNIOnCloseCallback, history: Boolean
): Long
private external fun declareBackgroundTransportEventsListenerViaJNI(
    ptr: Long, callback: JNITransportEventsCallback, onClose: JNIOnCloseCallback, history: Boolean
)
private external fun declareLinkEventsListenerViaJNI(
    ptr: Long, callback: JNILinkEventsCallback, onClose: JNIOnCloseCallback, history: Boolean,
    transportZid: ByteArray?, transportWhatAmI: Int, transportIsQos: Boolean, transportIsMulticast: Boolean
): Long
private external fun declareBackgroundLinkEventsListenerViaJNI(
    ptr: Long, callback: JNILinkEventsCallback, onClose: JNIOnCloseCallback, history: Boolean,
    transportZid: ByteArray?, transportWhatAmI: Int, transportIsQos: Boolean, transportIsMulticast: Boolean
)
```

**Transport filter convention:** Pass `transport.zid.bytes` as `transportZid` (or `null` for no
filter), along with the other Transport fields. Rust side calls
`Transport::new_from_fields(zid, whatami, is_qos, is_multicast)` to reconstruct the filter.

**Kotlin wrappers in JNISession:**

- `getTransports()`: calls `getTransportsViaJNI(ptr)` which returns `ArrayList` of `Any[]`
  encoding `[ByteArray(zid), Int(whatami), Boolean(isQos), Boolean(isMulticast)]`; constructs
  `Transport` objects
- `getLinks(transport: Transport?)`: passes transport fields or nulls; constructs `Link` objects
- `declareTransportEventsListener(callback, onClose, history)`: wires `JNITransportEventsCallback`,
  returns `TransportEventsListener(JNITransportEventsListener(rawPtr))`
- `declareBackgroundTransportEventsListener(callback, onClose, history)`: returns `Unit`
- `declareLinkEventsListener(callback, onClose, history, transport)`: passes transport filter fields
- `declareBackgroundLinkEventsListener(callback, onClose, history, transport)`: returns `Unit`

### 6. Extend `Session.kt`

Add internal delegation methods (follow `getPeersId()`/`getRoutersId()` pattern in structure,
but **register foreground listeners into `strongDeclarations`** like subscribers):

```kotlin
internal fun getTransports(): Result<List<Transport>>
internal fun getLinks(transport: Transport?): Result<List<Link>>
internal fun declareTransportEventsListener(...): Result<TransportEventsListener>
    // .onSuccess { strongDeclarations.add(it) }
internal fun declareBackgroundTransportEventsListener(...): Result<Unit>
internal fun declareLinkEventsListener(...): Result<LinkEventsListener>
    // .onSuccess { strongDeclarations.add(it) }
internal fun declareBackgroundLinkEventsListener(...): Result<Unit>
```

### 7. Extend `SessionInfo.kt`

**Snapshot queries:**
```kotlin
@Unstable fun transports(): Result<List<Transport>>
@Unstable fun links(transport: Transport? = null): Result<List<Link>>
```

**Transport event listeners — 6 overloads with `history: Boolean = false`:**
1. `fun declareTransportEventsListener(callback: TransportEventsCallback, onClose: (()->Unit)? = null, history: Boolean = false): Result<TransportEventsListener>`
2. `fun <R> declareTransportEventsListener(handler: TransportEventsHandler<R>, onClose: (()->Unit)? = null, history: Boolean = false): Result<TransportEventsListener>`
3. `fun declareTransportEventsListener(channel: Channel<TransportEvent>, onClose: (()->Unit)? = null, history: Boolean = false): Result<TransportEventsListener>`
4-6. Background variants returning `Result<Unit>`

**Link event listeners — same 6 overloads plus `transport: Transport? = null`.**

Handler→callback conversion: `TransportEventsCallback { event -> handler.handle(event) }`
(exact AdvancedPublisher.kt pattern).

Background listeners: **not** added to `strongDeclarations` — they live in zenoh session state
via `.background().wait()`.

### 8. New Rust file: `zenoh-jni/src/connectivity.rs`

Register in `lib.rs`: `mod connectivity;`

All JNI functions follow the pattern in `session.rs` (OwnedObject / Arc::from_raw / mem::forget).

**`Java_io_zenoh_jni_JNISession_getTransportsViaJNI`**
- `session.info().transports().wait()`
- Return Java `ArrayList`; each element is a Java Object array:
  `[ByteArray(zid 16 bytes), jint(whatami as i32), jboolean(isQos), jboolean(isMulticast)]`

**`Java_io_zenoh_jni_JNISession_getLinksViaJNI`** (takes transport filter fields)
- If `transportZid != null`: `Transport::new_from_fields(zid, whatami, is_qos, is_multicast)`,
  then `session.info().links().transport(t).wait()`
- Else: `session.info().links().wait()`
- Return `ArrayList`; each element Object array with all Link fields;
  `interfaces` as Java `String[]`; `-1` for absent numeric optionals; `null` for absent strings

**`Java_io_zenoh_jni_JNISession_declareTransportEventsListenerViaJNI`** (takes `history: jboolean`)
- Build callback using GlobalRef + Arc<JavaVM> + attach_current_thread_as_daemon
  (exact `advanced_publisher.rs` SetJniMatchingStatusCallback pattern)
- `session.info().transport_events_listener().history(history).callback(cb).wait()`
- Return `Arc::into_raw(Arc::new(listener))`

**`Java_io_zenoh_jni_JNISession_declareBackgroundTransportEventsListenerViaJNI`**
- Same callback; `.history(history).callback(cb).background().wait()`; returns void

**`Java_io_zenoh_jni_JNISession_declareLinkEventsListenerViaJNI`** (takes transport filter + history)
- Reconstruct optional transport filter from fields via `new_from_fields`
- Chain `.transport(t)` on builder if present
- Same callback pattern, return `Arc::into_raw(Arc::new(listener))`

**`Java_io_zenoh_jni_JNISession_declareBackgroundLinkEventsListenerViaJNI`** — background variant

**`Java_io_zenoh_jni_JNITransportEventsListener_freePtrViaJNI`**
**`Java_io_zenoh_jni_JNILinkEventsListener_freePtrViaJNI`**
- `Arc::from_raw(ptr)` to drop (same as `matching_listener.rs`)

### 9. Test file: `ConnectivityTest.kt`

Create `zenoh-kotlin/src/commonTest/kotlin/io/zenoh/ConnectivityTest.kt`:

- `testTransportsList` — two connected peer sessions; assert `info().transports()` non-empty with peer ZID
- `testLinksListNoFilter` — two connected sessions; assert `info().links()` non-empty
- `testLinksListWithFilter` — use `Transport` from `transports()` to call `links(transport)`;
  assert result is non-empty subset (and crucially: same transport snapshot works as filter)
- `testTransportEventsListenerPutDelete` — subscribe; connect second session; assert PUT event;
  disconnect; assert DELETE event
- `testTransportEventsHistory` — connect peer; then open listener with `history=true`;
  assert history PUT event delivered immediately
- `testLinkEventsListenerPutDelete` — same for link events
- `testLinkEventsListenerWithTransportFilter` — filter link events by `Transport` from event payload
  (demonstrates that event-sourced Transport snapshots are reusable as filters)
- `testBackgroundListeners` — background variants fire correctly without explicit undeclare

---

## Critical Files

| File | Action |
|------|--------|
| `zenoh-jni/src/connectivity.rs` | CREATE |
| `zenoh-jni/src/lib.rs` | ADD `mod connectivity;` |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/Transport.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/Link.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/TransportEvent.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/LinkEvent.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/TransportEventsListener.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/LinkEventsListener.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/TransportEventsCallback.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/TransportEventsHandler.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/TransportEventsChannelHandler.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/LinkEventsCallback.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/LinkEventsHandler.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/LinkEventsChannelHandler.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNITransportEventsListener.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNILinkEventsListener.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/JNITransportEventsCallback.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/JNILinkEventsCallback.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt` | EXTEND |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionInfo.kt` | EXTEND |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt` | EXTEND |
| `zenoh-kotlin/src/commonTest/kotlin/io/zenoh/ConnectivityTest.kt` | CREATE |

---

## Reused Patterns

- `JNISampleMissListener.kt` + `SampleMissListener.kt` → template for JNI listener wrappers
- `SampleMissCallback.kt` / `SampleMissHandler.kt` / `SampleMissChannelHandler.kt` → callback/handler files
- `SetJniMatchingStatusCallback` trait in `advanced_publisher.rs` → callback wiring template in Rust
- `ids_to_java_list` / `getPeersZidViaJNI` in `session.rs` → ArrayList return pattern for snapshots
- `MatchingListener::freePtrViaJNI` in `matching_listener.rs` → freePtrViaJNI for both listeners
- `Session.strongDeclarations.add(it)` in subscriber registration → lifecycle for foreground listeners

---

## Verification

1. `cd zenoh-jni && cargo build` (no extra flags; `unstable` + `internal` already on the zenoh dep)
2. `./gradlew test --tests "io.zenoh.ConnectivityTest"` — all connectivity tests pass
3. `./gradlew test` — full regression check

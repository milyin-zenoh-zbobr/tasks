# Connectivity API for zenoh-kotlin — Implementation Plan

## Context

The upstream zenoh Rust library added an unstable connectivity API enabling network-level introspection: snapshot queries for active transports and links, and listener subscriptions for transport/link lifecycle events. The zenoh-go binding already implements this. This task brings the equivalent API to zenoh-kotlin via JNI.

**Three blocking issues in prior plans (now resolved):**
1. Transport filter used zid-only — unsound because multiple transports to the same peer can exist (unicast + multicast). Fix: Arc pointer round-trip for Transport identity.
2. `Transport.isShm` — not available; `shared-memory` feature is absent from zenoh-jni/Cargo.toml (only `unstable` + `internal` are enabled). Fix: omit isShm entirely.
3. Verification used `cargo build --features unstable` — zenoh-jni has no local `unstable` feature (it's already enabled on the zenoh dep). Fix: plain `cargo build`.

**Closest analog:** `AdvancedSubscriber.declareSampleMissListener` + `SampleMissCallback`/`SampleMissHandler<R>`/`SampleMissChannelHandler` — dedicated callback/handler/channel types, 6 overloads (3 foreground + 3 background), `@Unstable`, delegated through JNISession → Session → SessionInfo.

---

## Upstream Rust API (all `#[zenoh_macros::unstable]`)

- `session.info().transports().wait()` → `Iterator<Transport>`
  - Transport fields: `zid: ZenohId`, `whatami: WhatAmI`, `is_qos: bool`, `is_multicast: bool`
  - **No `is_shm`** — feature-gated behind `shared-memory` which is not enabled
- `session.info().links()` → builder → `.transport(t)` (optional) → `.wait()` → `Iterator<Link>`
  - Link fields: `zid`, `src: Locator`, `dst: Locator`, `group: Option<Locator>`, `mtu: u16`, `is_streamed: bool`, `interfaces: Vec<String>`, `auth_identifier: Option<String>`, `priorities: Option<(u8,u8)>`, `reliability: Option<Reliability>`
- `session.info().transport_events_listener()` → `.history(bool)` → `.callback(f)` / `.background()` → `.wait()`
- `session.info().link_events_listener()` → `.history(bool)` → `.transport(t)` (optional) → `.callback(f)` / `.background()` → `.wait()`

---

## Implementation Plan

### 1. Transport Pointer Round-Trip Design

`Transport` objects returned from `session.info().transports()` are wrapped in `Arc<Transport>` and returned as raw pointers alongside their data fields. Kotlin stores these in `JNINativeTransport(ptr: Long)`. When filtering links or link event listeners by transport, Kotlin passes the ptr back to JNI, which recovers the `Arc`, clones the Transport, and forgets the Arc (preventing double-free).

**In Kotlin:** `Transport` is a **regular class** (not data class, to avoid issues with the internal ptr field propagating through `copy()`). It has public data properties and an `internal val jniNativeTransport: JNINativeTransport?`.

**In Rust:** `Arc::into_raw(Arc::new(transport))` stores the Transport; `Arc::from_raw(ptr) + clone + mem::forget` recovers it for filtering.

Use `0L` as the null sentinel for "no transport filter" in JNI calls.

---

### 2. New Kotlin Files

**Package `io.zenoh.connectivity`:**

- `Transport.kt` — `@Unstable` class: `val zid: ZenohId`, `val whatAmI: WhatAmI`, `val isQos: Boolean`, `val isMulticast: Boolean`, `internal val jniNativeTransport: JNINativeTransport?`
- `Link.kt` — `@Unstable data class`: all link fields (src/dst/group as String/String?, mtu as Int, interfaces as List<String>, authIdentifier?, priorityMin?/priorityMax? as Int?, reliability? reusing `io.zenoh.qos.Reliability`)
- `TransportEvent.kt` — `@Unstable data class`: `kind: SampleKind`, `transport: Transport`
- `LinkEvent.kt` — `@Unstable data class`: `kind: SampleKind`, `link: Link`
- `TransportEventsListener.kt` — `@Unstable class` implementing `SessionDeclaration + AutoCloseable`, wrapping `JNITransportEventsListener?`; same undeclare/close/finalize pattern as `SampleMissListener.kt`
- `LinkEventsListener.kt` — same pattern wrapping `JNILinkEventsListener?`

**Package `io.zenoh.handlers`** (follow SampleMiss* files exactly):

- `TransportEventsCallback.kt` — `@Unstable fun interface { fun run(event: TransportEvent) }`
- `TransportEventsHandler.kt` — `@Unstable interface<R>` with `handle(event)`, `receiver(): R`, `onClose()`
- `TransportEventsChannelHandler.kt` — `@Unstable internal class` wrapping `Channel<TransportEvent>`
- `LinkEventsCallback.kt`, `LinkEventsHandler.kt`, `LinkEventsChannelHandler.kt` — same for LinkEvent

**Package `io.zenoh.jni`:**

- `JNINativeTransport.kt` — `internal class` holding `ptr: Long`, implementing `AutoCloseable`; `close()` calls `freePtrViaJNI(ptr)`; `private external fun freePtrViaJNI(ptr: Long)`
- `JNITransportEventsListener.kt` — same pattern (holds ptr, close() calls freePtrViaJNI); same as `JNISampleMissListener.kt`/`JNIMatchingListener.kt`
- `JNILinkEventsListener.kt` — same

**Package `io.zenoh.jni.callbacks`:**

- `JNITransportEventsCallback.kt` — `internal fun interface` with `run(kind: Int, zidBytes: ByteArray, whatAmI: Int, isQos: Boolean, isMulticast: Boolean)`
- `JNILinkEventsCallback.kt` — `internal fun interface` with `run(kind: Int, zidBytes: ByteArray, src: String, dst: String, group: String?, mtu: Int, isStreamed: Boolean, interfaces: Array<String>, authIdentifier: String?, priorityMin: Int, priorityMax: Int, reliability: Int)`; `-1` sentinels for absent optional integers

---

### 3. Extend `JNISession.kt`

Add new `external` declarations and Kotlin wrappers:

- `getTransports()` → calls `getTransportsViaJNI(ptr)`: returns `ArrayList<Any>` where each element is `Array<Any>` containing `[jlong ptr, ByteArray zid, jint whatami, jboolean isQos, jboolean isMulticast]`; wraps each in `Transport(zid, whatAmI, isQos, isMulticast, JNINativeTransport(ptr))`
- `getLinks(transport: Transport?)` → calls `getLinksViaJNI(ptr, transport?.jniNativeTransport?.ptr ?: 0L)`: returns list of `Link` objects
- `declareTransportEventsListener(callback, onClose, history)` → `declareTransportEventsListenerViaJNI(ptr, jniCallback, onClose, history): Long` → `TransportEventsListener(JNITransportEventsListener(rawPtr))`
- `declareBackgroundTransportEventsListener(callback, onClose, history)` → `declareBackgroundTransportEventsListenerViaJNI(ptr, jniCallback, onClose, history)` → returns Unit
- `declareLinkEventsListener(callback, onClose, history, transport)` → `declareLinkEventsListenerViaJNI(ptr, jniCallback, onClose, history, transport?.jniNativeTransport?.ptr ?: 0L): Long`
- `declareBackgroundLinkEventsListener(callback, onClose, history, transport)` → same background variant

---

### 4. Extend `Session.kt`

Add internal delegation methods (following `getPeersId()`/`getRoutersId()` pattern):

- `internal fun getTransports(): Result<List<Transport>>`
- `internal fun getLinks(transport: Transport?): Result<List<Link>>`
- `internal fun declareTransportEventsListener(callback, onClose, history): Result<TransportEventsListener>`
- `internal fun declareBackgroundTransportEventsListener(callback, onClose, history): Result<Unit>`
- `internal fun declareLinkEventsListener(callback, onClose, history, transport): Result<LinkEventsListener>`
- `internal fun declareBackgroundLinkEventsListener(callback, onClose, history, transport): Result<Unit>`

---

### 5. Extend `SessionInfo.kt`

Public API — follow the 6-overload AdvancedSubscriber SampleMiss pattern per listener type:

**Snapshot queries:**
- `@Unstable fun transports(): Result<List<Transport>>`
- `@Unstable fun links(transport: Transport? = null): Result<List<Link>>`

**Transport event listeners (6 overloads):**
1. `fun declareTransportEventsListener(callback: TransportEventsCallback, onClose: (()->Unit)? = null, history: Boolean = false): Result<TransportEventsListener>`
2. `fun <R> declareTransportEventsListener(handler: TransportEventsHandler<R>, onClose: (()->Unit)? = null, history: Boolean = false): Result<TransportEventsListener>` — converts handler to callback: `TransportEventsCallback { event -> handler.handle(event) }`
3. `fun declareTransportEventsListener(channel: Channel<TransportEvent>, onClose: (()->Unit)? = null, history: Boolean = false): Result<TransportEventsListener>` — wraps in `TransportEventsChannelHandler`
4–6. Background variants returning `Result<Unit>` (no listener returned)

**Link event listeners (6 overloads):** same as above plus `transport: Transport? = null` parameter.

---

### 6. New Rust File: `zenoh-jni/src/connectivity.rs`

Register in `lib.rs`: `mod connectivity;`

**`Java_io_zenoh_jni_JNISession_getTransportsViaJNI`**
- `session.info().transports().wait()` (unstable, available via `features = ["unstable"]` on zenoh dep)
- For each Transport: `Arc::into_raw(Arc::new(transport))` → store as jlong
- Return Java ArrayList; each element is a Java Object array: `[jlong ptr, ByteArray(zid 16 bytes), jint(whatami), jboolean(isQos), jboolean(isMulticast)]`
- `mem::forget(session)` at end (standard pattern)

**`Java_io_zenoh_jni_JNINativeTransport_freePtrViaJNI`**
- `Arc::from_raw(ptr as *const Transport)` — drops the Arc

**`Java_io_zenoh_jni_JNISession_getLinksViaJNI`** (takes `session_ptr: *const Session`, `transport_ptr: jlong`)
- If `transport_ptr != 0`: recover Arc<Transport>, clone Transport, forget Arc, call `session.info().links().transport(t).wait()`
- Else: `session.info().links().wait()`
- Return ArrayList; each element is Object array with all Link fields; `interfaces` as Java `String[]` (not delimiter-joined)
- Optional fields use null objects or -1 int sentinels for numeric optionals

**`Java_io_zenoh_jni_JNISession_declareTransportEventsListenerViaJNI`** (takes history: jboolean)
- Build Rust callback calling JNITransportEventsCallback.run() via GlobalRef + JavaVM (same pattern as advanced_publisher.rs SetJniMatchingStatusCallback)
- `session.info().transport_events_listener().history(history).callback(cb).wait()`
- `Arc::into_raw(Arc::new(listener))`

**`Java_io_zenoh_jni_JNISession_declareBackgroundTransportEventsListenerViaJNI`**
- Same callback; `session.info().transport_events_listener().history(history).callback(cb).background().wait()`
- Returns void

**`Java_io_zenoh_jni_JNITransportEventsListener_freePtrViaJNI`**
- `Arc::from_raw(ptr)` to drop

**`declareLinkEventsListenerViaJNI` and background variant** — same patterns with additional `transport_ptr: jlong` for optional transport filter, applied via `.transport(t)` on the builder before `.callback(cb)`.

**`JNILinkEventsListener_freePtrViaJNI`** — same as transport variant.

---

### 7. Test File: `ConnectivityTest.kt`

Create `zenoh-kotlin/src/commonTest/kotlin/io/zenoh/ConnectivityTest.kt`:

- `testTransportsList` — two connected peer sessions; assert `info().transports()` returns list containing peer's ZenohId
- `testLinksListNoFilter` — two connected sessions; assert `info().links()` non-empty
- `testLinksListWithFilter` — use Transport from `transports()` to call `links(transport)` — assert subset returned
- `testTransportEventsListenerPutDelete` — subscribe; connect second session; assert TransportEvent with PUT SampleKind received; disconnect second; assert DELETE received
- `testTransportEventsHistory` — connect peer first; then open listener with `history=true`; assert history event delivered
- `testLinkEventsListenerPutDelete` — same for LinkEvents
- `testLinkEventsListenerWithTransportFilter` — filter link events by specific Transport
- `testBackgroundListeners` — background variants fire without explicit undeclare

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
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNINativeTransport.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNITransportEventsListener.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNILinkEventsListener.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/JNITransportEventsCallback.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/JNILinkEventsCallback.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt` | EXTEND |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionInfo.kt` | EXTEND |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt` | EXTEND (internal delegation) |
| `zenoh-kotlin/src/commonTest/kotlin/io/zenoh/ConnectivityTest.kt` | CREATE |

---

## Reused Existing Patterns

- `JNISampleMissListener.kt` + `SampleMissListener.kt` → template for `JNITransportEventsListener.kt`/`JNILinkEventsListener.kt`/`TransportEventsListener.kt`/`LinkEventsListener.kt`
- `SampleMissCallback.kt` / `SampleMissHandler.kt` / `SampleMissChannelHandler.kt` → template for all 6 new handler files
- `JNISession.getPeersZidViaJNI` + `ids_to_java_list` in `session.rs` → template for `getTransportsViaJNI`/`getLinksViaJNI` return patterns
- `MatchingListener::freePtrViaJNI` in `matching_listener.rs` → template for all three `freePtrViaJNI` functions
- `OwnedObject` + `Arc::from_raw/into_raw/mem::forget` pattern throughout `session.rs` and `advanced_publisher.rs` → template for transport pointer round-trip

---

## Verification

1. `cd zenoh-jni && cargo build` — validates Rust JNI compiles (no `--features` flag needed; unstable already enabled on zenoh dep)
2. `./gradlew test --tests "io.zenoh.ConnectivityTest"` — validates all connectivity tests pass
3. `./gradlew test` — validates no regressions in existing tests

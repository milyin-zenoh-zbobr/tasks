# Connectivity API for zenoh-kotlin — Implementation Plan

## Context

zenoh-kotlin#647 requests a connectivity API that mirrors the one added to zenoh-go. The API should expose:
1. **Synchronous snapshot getters**: `transports()` and `links(transport?)` on `SessionInfo`
2. **Event listeners**: `declareTransportEventsListener(...)` and `declareLinkEventsListener(...)` on `SessionInfo`, with owned and background variants

The zenoh Rust crate (1.8.0, `features = ["unstable", "internal"]`) already provides:
- `session.info().transports().wait()` → iterator of `Transport`
- `session.info().links()[.transport(t)].wait()` → iterator of `Link`
- `session.info().transport_events_listener().history(bool).callback(fn).wait()` → `TransportEventsListener<()>`
- `session.info().link_events_listener().history(bool)[.transport(t)].callback(fn).wait()` → `LinkEventsListener<()>`
- Background variants via `.background().wait()` → `Result<()>`
- `Transport::new_from_fields(zid, whatami, is_qos, is_multicast)` (`#[internal]`) for Rust-side reconstruction from Kotlin-passed fields

The previous plan (ctx_rec_7) had the right direction but was rejected (ctx_rec_8) for missing: full Kotlin type set, callback/handler/channel strategy for non-ZenohType events, `@Unstable` annotations, listener lifecycle wiring, and concrete test coverage.

**Closest analogs**: `SampleMissListener` / `MatchingListener` for owned listener lifecycle; `JNILiveliness` for session-level JNI object pattern; `JNISampleMissListenerCallback` for non-ZenohType JNI callback encoding.

---

## New Kotlin Types (all `@Unstable`)

### Data classes (`io.zenoh.session` package)

- **`Transport`**: `data class(val zid: ZenohId, val whatami: WhatAmI, val isQos: Boolean, val isMulticast: Boolean)`
- **`Link`**: `data class(val zid: ZenohId, val src: String, val dst: String, val group: String?, val mtu: Int, val isStreamed: Boolean, val interfaces: List<String>, val authIdentifier: String?, val priorities: Pair<Byte,Byte>?, val reliability: Reliability?)`
  - `src`/`dst`/`group` are Locator string representations
  - `interfaces` joined/split via `";"` across JNI boundary
  - `priorities` is `(priorityMin, priorityMax)` as `Pair<Byte,Byte>?`; `null` when transport has no QoS
  - `reliability` is `Reliability?`; `null` when transport has no QoS
- **`TransportEvent`**: `data class(val kind: SampleKind, val transport: Transport)`
- **`LinkEvent`**: `data class(val kind: SampleKind, val link: Link)`

### Owned listener handles (`io.zenoh.session` package)

- **`TransportEventsListener`**: wraps `JNITransportEventsListener?`, implements `SessionDeclaration` + `AutoCloseable`. Methods: `isValid()`, `undeclare()`, `close()`, `finalize()`. Identical structure to `SampleMissListener`.
- **`LinkEventsListener`**: same pattern, wraps `JNILinkEventsListener?`.

### Callback/handler/channel types (`io.zenoh.handlers` package, all `@Unstable`)

Because `TransportEvent` and `LinkEvent` are not `ZenohType`, dedicate per-type variants (same approach as `SampleMiss*` / `Matching*`):

- `TransportEventCallback` — `fun interface { fun run(event: TransportEvent) }`
- `TransportEventHandler<R>` — `interface { fun handle(TransportEvent); fun receiver(): R; fun onClose() }`
- `TransportEventChannelHandler` — internal class wrapping `Channel<TransportEvent>`, implements `TransportEventHandler<Channel<TransportEvent>>`
- `LinkEventCallback`, `LinkEventHandler<R>`, `LinkEventChannelHandler` — same pattern for `LinkEvent`

---

## JNI Layer

### Internal JNI callback interfaces (`io.zenoh.jni.callbacks` package)

- **`JNITransportCallback`** — per-item callback for synchronous `getTransports()`:
  `fun interface { fun receive(zid: ByteArray, whatami: Int, isQos: Boolean, isMulticast: Boolean) }`
- **`JNILinkCallback`** — per-item callback for synchronous `getLinks()`:
  `fun interface { fun receive(zid: ByteArray, src: String, dst: String, group: String?, mtu: Int, isStreamed: Boolean, interfaces: String, authIdentifier: String?, hasPriorities: Boolean, priorityMin: Byte, priorityMax: Byte, hasReliability: Boolean, reliabilityOrdinal: Int) }`
  (interfaces passed as `";"` joined string)
- **`JNITransportEventCallback`** — for listener events:
  `fun interface { fun run(kind: Int, zid: ByteArray, whatami: Int, isQos: Boolean, isMulticast: Boolean) }`
- **`JNILinkEventCallback`** — for listener events:
  `fun interface { fun run(kind: Int, zid: ByteArray, src: String, dst: String, group: String?, mtu: Int, isStreamed: Boolean, interfaces: String, authIdentifier: String?, hasPriorities: Boolean, priorityMin: Byte, priorityMax: Byte, hasReliability: Boolean, reliabilityOrdinal: Int) }`

### Internal JNI handle classes (`io.zenoh.jni` package)

- **`JNITransportEventsListener(ptr: Long)`**: `fun close() { freePtrViaJNI(ptr) }`, `private external fun freePtrViaJNI(ptr: Long)`
- **`JNILinkEventsListener(ptr: Long)`**: same pattern

### JNISession additions (`io.zenoh.jni.JNISession`)

New Kotlin methods (all `internal`):
```
fun getTransports(): Result<List<Transport>>
  // calls getTransportsViaJNI(sessionPtr.get(), callback) accumulating into mutable list

fun getLinks(transport: Transport? = null): Result<List<Link>>
  // calls getLinksViaJNI(sessionPtr.get(), hasFilter, [transport fields], callback)

fun declareTransportEventsListener(callback: TransportEventCallback, onClose: () -> Unit, history: Boolean): Result<TransportEventsListener>
fun declareBackgroundTransportEventsListener(callback: TransportEventCallback, onClose: () -> Unit, history: Boolean): Result<Unit>
fun declareLinkEventsListener(callback: LinkEventCallback, onClose: () -> Unit, history: Boolean, transport: Transport? = null): Result<LinkEventsListener>
fun declareBackgroundLinkEventsListener(callback: LinkEventCallback, onClose: () -> Unit, history: Boolean, transport: Transport? = null): Result<Unit>
```

New private external functions:
```
getTransportsViaJNI(sessionPtr: Long, callback: JNITransportCallback)
getLinksViaJNI(sessionPtr: Long, hasTransportFilter: Boolean, zid: ByteArray, whatami: Int, isQos: Boolean, isMulticast: Boolean, callback: JNILinkCallback)
declareTransportEventsListenerViaJNI(sessionPtr: Long, callback: JNITransportEventCallback, onClose: JNIOnCloseCallback, history: Boolean): Long
declareBackgroundTransportEventsListenerViaJNI(sessionPtr: Long, callback: JNITransportEventCallback, onClose: JNIOnCloseCallback, history: Boolean)
declareLinkEventsListenerViaJNI(sessionPtr: Long, callback: JNILinkEventCallback, onClose: JNIOnCloseCallback, history: Boolean, hasTransportFilter: Boolean, zid: ByteArray, whatami: Int, isQos: Boolean, isMulticast: Boolean): Long
declareBackgroundLinkEventsListenerViaJNI(sessionPtr: Long, callback: JNILinkEventCallback, onClose: JNIOnCloseCallback, history: Boolean, hasTransportFilter: Boolean, zid: ByteArray, whatami: Int, isQos: Boolean, isMulticast: Boolean)
```

---

## SessionInfo additions

All methods `@Unstable`. Pattern mirrors `Liveliness`: access `session.jniSession ?: throw Session.sessionClosedException`.

### Synchronous getters
```kotlin
fun transports(): Result<List<Transport>>
fun links(transport: Transport? = null): Result<List<Link>>
```

### TransportEventsListener — 6 overloads (3 owned + 3 background)

**Owned** (return `Result<TransportEventsListener>`):
1. `declareTransportEventsListener(callback: TransportEventCallback, history: Boolean = false, onClose: (() -> Unit)? = null)`
2. `<R> declareTransportEventsListener(handler: TransportEventHandler<R>, history: Boolean = false, onClose: (() -> Unit)? = null)` — wraps handler into callback internally
3. `declareTransportEventsListener(channel: Channel<TransportEvent>, history: Boolean = false, onClose: (() -> Unit)? = null)` — wraps into `TransportEventChannelHandler`

**Background** (return `Result<Unit>`):
4. `declareBackgroundTransportEventsListener(callback: TransportEventCallback, history: Boolean = false, onClose: (() -> Unit)? = null)`
5. `<R> declareBackgroundTransportEventsListener(handler: TransportEventHandler<R>, ...)`
6. `declareBackgroundTransportEventsListener(channel: Channel<TransportEvent>, ...)`

### LinkEventsListener — 6 overloads (3 owned + 3 background)

Same structure but each overload gains `transport: Transport? = null` parameter. Types: `LinkEventCallback`, `LinkEventHandler<R>`, `Channel<LinkEvent>`.

---

## Rust JNI — new file `zenoh-jni/src/session_info.rs`

Add `mod session_info;` to `zenoh-jni/src/lib.rs`.

### `Java_io_zenoh_jni_JNISession_getTransportsViaJNI`
- Borrow session via `Arc::from_raw` + `std::mem::forget`
- `session.info().transports().wait()` → iterate
- Per transport: `env.call_method(callback, "receive", "([BIZZ)V", [zid_bytes, whatami as i32, is_qos, is_multicast])`
- `whatami` as integer: `Router=1, Peer=2, Client=4` (matches Kotlin `WhatAmI.value`)

### `Java_io_zenoh_jni_JNISession_getLinksViaJNI`
- If `has_transport_filter`, reconstruct `Transport::new_from_fields(...)` and call `.links().transport(t)`
- Per link: call `JNILinkCallback.receive` with all link fields; `interfaces` as `link.interfaces().join(";")`; `mtu` as `i32`; reliability ordinal `0=BestEffort/1=Reliable`

### `Java_io_zenoh_jni_JNISession_declareTransportEventsListenerViaJNI`
- `load_on_close`, `get_callback_global_ref`, build closure calling `JNITransportEventCallback.run` via `attach_current_thread_as_daemon`
- `session.info().transport_events_listener().history(history).callback(closure).wait()?`
- Return `Arc::into_raw(Arc::new(listener))` as `*const TransportEventsListener<()>`

### `Java_io_zenoh_jni_JNISession_declareBackgroundTransportEventsListenerViaJNI`
- Same but chain `.background()` before `.wait()`; no return value

### `Java_io_zenoh_jni_JNISession_declareLinkEventsListenerViaJNI`
- Same closure pattern; if `has_transport_filter`, chain `.transport(Transport::new_from_fields(...))`
- Return raw ptr to `LinkEventsListener<()>`

### `Java_io_zenoh_jni_JNISession_declareBackgroundLinkEventsListenerViaJNI`
- Same but `.background()`

### `Java_io_zenoh_jni_JNITransportEventsListener_freePtrViaJNI`
- `Arc::from_raw(ptr: *const TransportEventsListener<()>)` — drop triggers `undeclare_on_drop`

### `Java_io_zenoh_jni_JNILinkEventsListener_freePtrViaJNI`
- `Arc::from_raw(ptr: *const LinkEventsListener<()>)` — drop triggers `undeclare_on_drop`

---

## File Summary

### New Kotlin files
| File | Purpose |
|------|---------|
| `session/Transport.kt` | `@Unstable data class Transport` |
| `session/Link.kt` | `@Unstable data class Link` |
| `session/TransportEvent.kt` | `@Unstable data class TransportEvent` |
| `session/LinkEvent.kt` | `@Unstable data class LinkEvent` |
| `session/TransportEventsListener.kt` | Owned listener handle (SessionDeclaration) |
| `session/LinkEventsListener.kt` | Owned listener handle (SessionDeclaration) |
| `handlers/TransportEventCallback.kt` | Public fun interface |
| `handlers/TransportEventHandler.kt` | Public interface with receiver |
| `handlers/TransportEventChannelHandler.kt` | Internal channel wrapper |
| `handlers/LinkEventCallback.kt` | Public fun interface |
| `handlers/LinkEventHandler.kt` | Public interface with receiver |
| `handlers/LinkEventChannelHandler.kt` | Internal channel wrapper |
| `jni/callbacks/JNITransportCallback.kt` | JNI per-item callback (getTransports) |
| `jni/callbacks/JNILinkCallback.kt` | JNI per-item callback (getLinks) |
| `jni/callbacks/JNITransportEventCallback.kt` | JNI event callback (listener) |
| `jni/callbacks/JNILinkEventCallback.kt` | JNI event callback (listener) |
| `jni/JNITransportEventsListener.kt` | Internal ptr wrapper with freePtrViaJNI |
| `jni/JNILinkEventsListener.kt` | Internal ptr wrapper with freePtrViaJNI |

### Modified Kotlin files
| File | Changes |
|------|---------|
| `jni/JNISession.kt` | 6 new methods + 6 new `private external fun` declarations |
| `session/SessionInfo.kt` | 2 sync getters + 12 listener overloads (all `@Unstable`) |

### New Rust files
| File | Contents |
|------|---------|
| `zenoh-jni/src/session_info.rs` | 8 JNI C functions |

### Modified Rust files
| File | Change |
|------|--------|
| `zenoh-jni/src/lib.rs` | Add `mod session_info;` |

### New test file
`zenoh-kotlin/src/commonTest/kotlin/io/zenoh/ConnectivityTest.kt`

---

## Test Coverage (`ConnectivityTest.kt`)

Tests require two sessions: one listening (`mode: "peer", listen: [...]`), one connecting (`mode: "peer", connect: [...]`).

| Test | What it verifies |
|------|-----------------|
| `transports() non-empty` | Connected session sees peer transport with correct zid/whatami |
| `transports() empty` | Isolated session returns empty list |
| `links() non-empty` | Connected session has at least one link |
| `links() empty` | Isolated session returns empty list |
| `links(transport) filter` | `links(transport)` returns subset; `links()` ≥ `links(t)` |
| `transport events listener - owned, history=false` | Receives PUT event on peer connect; undeclare works |
| `transport events listener - owned, history=true` | Receives past transports as PUT events after register |
| `transport events listener - background` | Background listener fires callback; returns Unit |
| `transport events listener - DELETE event` | Receives DELETE on peer disconnect |
| `link events listener - owned` | Receives PUT event when link is established |
| `link events listener - transport filter` | Only events from the filtered transport received |
| `link events listener - background` | Background listener fires; returns Unit |
| `link events listener - history` | History=true replays existing links |
| `listener cleanup on close` | `listener.close()` stops further callbacks |
| `listener cleanup on session close` | Closing session undeclares all owned listeners |

---

## Verification

1. `cd zenoh-jni && cargo build` — Rust compiles without errors
2. `./gradlew :zenoh-kotlin:jvmTest --tests "io.zenoh.ConnectivityTest"` — all connectivity tests pass
3. `./gradlew :zenoh-kotlin:jvmTest` — no regressions in existing tests (SessionInfoTest, AdvancedPubSubTest, etc.)

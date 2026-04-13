# Implementation Plan: Connectivity API for zenoh-kotlin

## Reference
- **Issue**: https://github.com/eclipse-zenoh/zenoh-kotlin/issues/647
- **Analog in Go**: https://github.com/eclipse-zenoh/zenoh-go/pull/17
- **Rust API**: `zenoh::session::info()` → `transports()`, `links()`, `transport_events_listener()`, `link_events_listener()`
- **Closest Kotlin analogs**: `Liveliness` (for event listener pattern) and `MatchingListener` (for undeclarable listener)

---

## Architecture

The connectivity API follows the same 3-layer pattern used throughout zenoh-kotlin:
1. **Kotlin layer**: public-facing data types, listener objects, `SessionInfo` methods
2. **JNI Kotlin bridge layer**: callback interfaces + `JNIConnectivity` object + listener JNI handles
3. **Rust JNI layer**: new `connectivity.rs` wiring zenoh's Rust API to JVM callbacks

Key design choice (from the Go binding task description): **Transport and Link are pure Kotlin snapshots** — all fields are extracted by Rust and passed as primitives/strings across the JNI boundary. No C/Rust pointer is held by these types. This avoids lifecycle complexity.

---

## New Kotlin Types (package `io.zenoh.session.connectivity`)

### `Transport` (data class, `@Unstable`)
- `zid: ZenohId`
- `whatAmI: WhatAmI`
- `isQos: Boolean`
- `isMulticast: Boolean`

### `Link` (data class, `@Unstable`)
- `zid: ZenohId`
- `src: String`
- `dst: String`
- `group: String?`
- `mtu: Int`
- `isStreamed: Boolean`
- `interfaces: List<String>`
- `authIdentifier: String?`
- `priorities: PriorityRange?`
- `reliability: Reliability?`

### `PriorityRange` (data class)
- `min: Int`, `max: Int`

### `TransportEvent` (data class, `@Unstable`)
- `kind: SampleKind`
- `transport: Transport`

### `LinkEvent` (data class, `@Unstable`)
- `kind: SampleKind`
- `link: Link`

### `TransportEventsListener` (`@Unstable`, `SessionDeclaration`, `AutoCloseable`)
- Holds `JNITransportEventsListener?`
- Methods: `undeclare()`, `close()`, `isValid()`
- Pattern: same as `MatchingListener`

### `LinkEventsListener` (`@Unstable`, `SessionDeclaration`, `AutoCloseable`)
- Holds `JNILinkEventsListener?`
- Methods: `undeclare()`, `close()`, `isValid()`

---

## JNI Callback Interfaces (package `io.zenoh.jni.callbacks`)

All follow the SAM pattern (`fun interface`):

- **`JNITransportCallback`**: called once per transport in `getTransports`
  - `run(zid: ByteArray, whatAmI: Int, isQos: Boolean, isMulticast: Boolean)`

- **`JNITransportEventCallback`**: called for each transport event
  - `run(kind: Int, zid: ByteArray, whatAmI: Int, isQos: Boolean, isMulticast: Boolean)`

- **`JNILinkCallback`**: called once per link in `getLinks`
  - `run(zid: ByteArray, src: String, dst: String, group: String?, mtu: Int, isStreamed: Boolean, interfaces: Array<String>, authIdentifier: String?, hasPriorities: Boolean, prioritiesMin: Int, prioritiesMax: Int, hasReliability: Boolean, reliability: Int)`

- **`JNILinkEventCallback`**: called for each link event
  - `run(kind: Int, zid: ByteArray, src: String, dst: String, group: String?, mtu: Int, isStreamed: Boolean, interfaces: Array<String>, authIdentifier: String?, hasPriorities: Boolean, prioritiesMin: Int, prioritiesMax: Int, hasReliability: Boolean, reliability: Int)`

---

## JNI Bridge Classes

### `JNIConnectivity` (internal object)
Declares 4 external JNI functions:
1. `getTransportsViaJNI(sessionPtr, callback: JNITransportCallback, onClose: JNIOnCloseCallback)`
2. `getLinksViaJNI(sessionPtr, transportZid: ByteArray?, transportWhatAmI: Int, transportIsQos: Boolean, transportIsMulticast: Boolean, hasTransportFilter: Boolean, callback: JNILinkCallback, onClose: JNIOnCloseCallback)`
3. `declareTransportEventsListenerViaJNI(sessionPtr, callback: JNITransportEventCallback, history: Boolean, onClose: JNIOnCloseCallback): Long`
4. `declareLinkEventsListenerViaJNI(sessionPtr, callback: JNILinkEventCallback, history: Boolean, onClose: JNIOnCloseCallback): Long`

Contains helper methods to assemble `Transport`/`Link` from callback parameters.

### `JNITransportEventsListener` (internal class)
- Holds `ptr: Long`
- `close()` calls `freePtrViaJNI(ptr)`

### `JNILinkEventsListener` (internal class)
- Holds `ptr: Long`
- `close()` calls `freePtrViaJNI(ptr)`

---

## `SessionInfo` changes

Add 4 methods, all `@Unstable`:

```
fun transports(): Result<List<Transport>>
fun links(transport: Transport? = null): Result<List<Link>>
fun declareTransportEventsListener(callback: Callback<TransportEvent>, history: Boolean = false, onClose: (() -> Unit)? = null): Result<TransportEventsListener>
fun declareLinkEventsListener(callback: Callback<LinkEvent>, history: Boolean = false, onClose: (() -> Unit)? = null): Result<LinkEventsListener>
```

---

## Rust JNI Layer: `zenoh-jni/src/connectivity.rs`

5 JNI functions:

1. **`Java_io_zenoh_jni_JNIConnectivity_getTransportsViaJNI`**
   - Calls `session.info().transports().wait()`
   - For each `Transport`, calls JVM callback with extracted fields

2. **`Java_io_zenoh_jni_JNIConnectivity_getLinksViaJNI`**
   - Calls `session.info().links().wait()`
   - If `hasTransportFilter=true`, reconstructs a `Transport` from fields and passes it to `links().transport(...)`
   - For each `Link`, calls JVM callback with extracted fields

3. **`Java_io_zenoh_jni_JNIConnectivity_declareTransportEventsListenerViaJNI`**
   - Calls `session.info().transport_events_listener().history(history).callback(closure).wait()`
   - Returns `Arc::into_raw` of the listener
   - Closure calls JVM callback with event fields

4. **`Java_io_zenoh_jni_JNIConnectivity_declareLinkEventsListenerViaJNI`**
   - Calls `session.info().link_events_listener().history(history).callback(closure).wait()`
   - Returns `Arc::into_raw` of the listener

5. **`Java_io_zenoh_jni_JNITransportEventsListener_freePtrViaJNI`**

6. **`Java_io_zenoh_jni_JNILinkEventsListener_freePtrViaJNI`**

---

## Files Modified/Created

### Created:
- `zenoh-kotlin/.../session/connectivity/Transport.kt`
- `zenoh-kotlin/.../session/connectivity/Link.kt`
- `zenoh-kotlin/.../session/connectivity/PriorityRange.kt`
- `zenoh-kotlin/.../session/connectivity/TransportEvent.kt`
- `zenoh-kotlin/.../session/connectivity/LinkEvent.kt`
- `zenoh-kotlin/.../session/connectivity/TransportEventsListener.kt`
- `zenoh-kotlin/.../session/connectivity/LinkEventsListener.kt`
- `zenoh-kotlin/.../jni/JNIConnectivity.kt`
- `zenoh-kotlin/.../jni/JNITransportEventsListener.kt`
- `zenoh-kotlin/.../jni/JNILinkEventsListener.kt`
- `zenoh-kotlin/.../jni/callbacks/JNITransportCallback.kt`
- `zenoh-kotlin/.../jni/callbacks/JNITransportEventCallback.kt`
- `zenoh-kotlin/.../jni/callbacks/JNILinkCallback.kt`
- `zenoh-kotlin/.../jni/callbacks/JNILinkEventCallback.kt`
- `zenoh-jni/src/connectivity.rs`

### Modified:
- `zenoh-kotlin/.../session/SessionInfo.kt` — 4 new methods
- `zenoh-jni/src/lib.rs` — add `pub mod connectivity;`

---

## Notes

- All new public API is marked `@Unstable` (matches the Rust API's `#[zenoh_macros::unstable]` annotations)
- The `@Unstable` annotation is imported from `io.zenoh.annotations.Unstable`
- Transport filter for `links()` is optional — when null, calls the plain `links()` Rust builder; when non-null, needs special handling in Rust (reconstructing the filter using `info::Transport` fields)
- The `Reliability` enum already exists in `io.zenoh.qos.Reliability` and can be reused
- `WhatAmI` already exists in `io.zenoh.config.WhatAmI`
- Error handling follows existing pattern: `throw_exception!` in Rust, `Result` in Kotlin

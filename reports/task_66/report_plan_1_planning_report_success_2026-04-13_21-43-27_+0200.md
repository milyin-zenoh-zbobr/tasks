# Connectivity API for zenoh-kotlin — Implementation Plan

## Context

The zenoh core library (Rust) added a connectivity API (`zenoh/src/api/connectivity.rs`, `zenoh/src/api/info.rs`) that exposes transport-level and link-level network introspection. This includes:
- Querying currently active transports (connections to remote peers)
- Querying currently active links (physical network paths)
- Subscribing to transport lifecycle events (open/close)
- Subscribing to link lifecycle events (add/remove)

The zenoh-go binding already implemented this in PR #17. This task brings the same API to zenoh-kotlin, following the same JNI/callback architecture used throughout the codebase.

All new APIs are marked `@Unstable` since the underlying Rust API is `#[zenoh_macros::unstable]`.

**Closest analog in codebase:** `MatchingListener` (in `zenoh-jni/src/ext/matching_listener.rs` + `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/MatchingListener.kt`) — a callback-based listener registered via JNI, returned as an ownable pointer, with `undeclare()`/background variants. Exactly the same pattern needed here for `TransportEventsListener` and `LinkEventsListener`.

---

## Architecture

### Rust zenoh API used (unstable)

- `session.info().transports().wait()` → `Iterator<Transport>`
- `session.info().links().wait()` → `Iterator<Link>`
- `session.declare_transport_events_listener_inner(callback, history, drop_notifier)` → `Arc<TransportEventsListenerState>`
- `session.declare_transport_links_listener_inner(callback, history, transport_filter, drop_notifier)` → `Arc<LinkEventsListenerState>`
- Corresponding `undeclare_*_inner` methods for cleanup

`Transport` fields: `zid: ZenohId`, `whatami: WhatAmI`, `is_qos: bool`, `is_multicast: bool`

`Link` fields: `zid: ZenohId`, `src: Locator`, `dst: Locator`, `group: Option<Locator>`, `mtu: u16`, `is_streamed: bool`, `interfaces: Vec<String>`, `auth_identifier: Option<String>`, `priorities: Option<(u8, u8)>`, `reliability: Option<Reliability>`

`TransportEvent` fields: `kind: SampleKind`, `transport: Transport`
`LinkEvent` fields: `kind: SampleKind`, `link: Link`

---

## Implementation Plan

### 1. New data classes (Kotlin) — `io.zenoh.connectivity` package

Create `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/`:

**`Transport.kt`** — `@Unstable data class Transport(val zid: ZenohId, val whatAmI: WhatAmI, val isQos: Boolean, val isMulticast: Boolean)`

**`Link.kt`** — `@Unstable data class Link(val zid: ZenohId, val src: String, val dst: String, val group: String?, val mtu: Int, val isStreamed: Boolean, val interfaces: List<String>, val authIdentifier: String?, val priorityMin: Int?, val priorityMax: Int?, val reliability: Reliability?)`

**`TransportEvent.kt`** — `@Unstable data class TransportEvent(val kind: SampleKind, val transport: Transport)`

**`LinkEvent.kt`** — `@Unstable data class LinkEvent(val kind: SampleKind, val link: Link)`

**`TransportEventsListener.kt`** — `@Unstable class TransportEventsListener : SessionDeclaration, AutoCloseable` — wraps `JNITransportEventsListener`, implements `undeclare()` and `close()` (same pattern as `MatchingListener.kt`)

**`LinkEventsListener.kt`** — same pattern for links

### 2. JNI callback interfaces (Kotlin)

In `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/`:

**`JNITransportEventsCallback.kt`**:
```kotlin
internal fun interface JNITransportEventsCallback {
    fun run(kind: Int, zidBytes: ByteArray, whatAmI: Int, isQos: Boolean, isMulticast: Boolean)
}
```

**`JNILinkEventsCallback.kt`**:
```kotlin
internal fun interface JNILinkEventsCallback {
    fun run(kind: Int, zidBytes: ByteArray, src: String, dst: String, group: String?,
            mtu: Int, isStreamed: Boolean, interfaces: String,  // pipe-joined
            authIdentifier: String?, priorityMin: Int, priorityMax: Int, reliability: Int)
}
```
Note: `interfaces` is passed as pipe-separated string (`|` delimiter) for simplicity. `-1` sentinel values for absent optional integers.

### 3. JNI listener wrappers (Kotlin)

In `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/`:

**`JNITransportEventsListener.kt`** — holds `ptr: Long`, calls `freePtrViaJNI(ptr)` on close. `private external fun freePtrViaJNI(ptr: Long)`

**`JNILinkEventsListener.kt`** — same pattern.

### 4. Extend JNISession.kt

Add to `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`:

- `fun getTransports(): Result<List<Transport>>` — calls `getTransportsViaJNI(sessionPtr)`, constructs Transport objects from returned data
- `fun getLinks(): Result<List<Link>>` — calls `getLinksViaJNI(sessionPtr)`, constructs Link objects
- `fun declareTransportEventsListener(callback, onClose): Result<TransportEventsListener>` — wires up `JNITransportEventsCallback`, calls `declareTransportEventsListenerViaJNI`
- `fun declareBackgroundTransportEventsListener(callback)` — calls `declareBackgroundTransportEventsListenerViaJNI`
- `fun declareLinkEventsListener(callback, onClose): Result<LinkEventsListener>` — same pattern
- `fun declareBackgroundLinkEventsListener(callback)` — same pattern

**External declarations:**
```kotlin
private external fun getTransportsViaJNI(sessionPtr: Long): List<Any>
private external fun getLinksViaJNI(sessionPtr: Long): List<Any>
private external fun declareTransportEventsListenerViaJNI(sessionPtr: Long, callback: JNITransportEventsCallback, onClose: JNIOnCloseCallback): Long
private external fun declareBackgroundTransportEventsListenerViaJNI(sessionPtr: Long, callback: JNITransportEventsCallback, onClose: JNIOnCloseCallback)
private external fun declareLinkEventsListenerViaJNI(sessionPtr: Long, callback: JNILinkEventsCallback, onClose: JNIOnCloseCallback): Long
private external fun declareBackgroundLinkEventsListenerViaJNI(sessionPtr: Long, callback: JNILinkEventsCallback, onClose: JNIOnCloseCallback)
```

For `getTransports`/`getLinks`, the Rust layer returns an ArrayList of Object arrays, analogous to how `getPeersZidViaJNI` returns an ArrayList. Each entry encodes all fields of the struct as JVM primitives/strings.

### 5. Extend SessionInfo.kt

Add to `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionInfo.kt`:

```kotlin
@Unstable fun transports(): Result<List<Transport>>
@Unstable fun links(): Result<List<Link>>
@Unstable fun declareTransportEventsListener(callback: Callback<TransportEvent>, onClose: () -> Unit = {}): Result<TransportEventsListener>
@Unstable fun declareBackgroundTransportEventsListener(callback: Callback<TransportEvent>)
@Unstable fun declareLinkEventsListener(callback: Callback<LinkEvent>, onClose: () -> Unit = {}): Result<LinkEventsListener>
@Unstable fun declareBackgroundLinkEventsListener(callback: Callback<LinkEvent>)
```

All delegate to corresponding `Session` internal methods (which call into JNISession).

### 6. New Rust file: `zenoh-jni/src/connectivity.rs`

JNI functions to implement:

**`Java_io_zenoh_jni_JNISession_getTransportsViaJNI`**
- Calls `session.info().transports().wait()` (needs `#[cfg(feature = "unstable")]` / internal feature)
- Returns `jobject` (Java ArrayList), each element is an Object array: `[ByteArray(zid 16 bytes), jint(whatami), jboolean(isQos), jboolean(isMulticast)]`

**`Java_io_zenoh_jni_JNISession_getLinksViaJNI`**
- Calls `session.info().links().wait()`
- Returns ArrayList of Object arrays encoding all Link fields

**`Java_io_zenoh_jni_JNISession_declareTransportEventsListenerViaJNI`**
- Creates a `Callback<TransportEvent>` that calls back into JVM via `JNITransportEventsCallback.run(kind, zidBytes, whatami, isQos, isMulticast)`
- Calls `session.declare_transport_events_listener_inner(callback, /*history=*/false, None)`
- Returns raw pointer to `Arc<TransportEventsListenerState>`

**`Java_io_zenoh_jni_JNISession_declareBackgroundTransportEventsListenerViaJNI`**
- Same callback setup, but drops the returned listener state (stores Arc in session state, no ptr returned)

**`Java_io_zenoh_jni_JNISession_declareLinkEventsListenerViaJNI`** and **`...Background...`**
- Same pattern for links; callback marshals all Link fields as flat JVM types

**`Java_io_zenoh_jni_JNITransportEventsListener_freePtrViaJNI`**
- `Arc::from_raw(ptr)` to drop the listener state and deregister callback

**`Java_io_zenoh_jni_JNILinkEventsListener_freePtrViaJNI`** — same for links.

Register in `zenoh-jni/src/lib.rs`:
```rust
mod connectivity;
```

### 7. Test file

Create `zenoh-kotlin/src/commonTest/kotlin/io/zenoh/ConnectivityTest.kt`:
- `testTransportsList`: Opens two connected peer sessions, asserts `info().transports()` returns list with 1 transport of correct ZID
- `testLinksList`: Opens two connected peers, asserts `info().links()` returns links with non-empty src/dst strings
- `testTransportEventsListener`: Opens listener session, subscribes to transport events, connects second session, asserts PUT event received with correct transport ZID; then closes second session, asserts DELETE event received
- `testLinkEventsListener`: Similar for link events
- `testBackgroundListeners`: Verifies background variants fire correctly without explicit undeclare

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
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/JNITransportEventsCallback.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/JNILinkEventsCallback.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNITransportEventsListener.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNILinkEventsListener.kt` | CREATE |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt` | EXTEND |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionInfo.kt` | EXTEND |
| `zenoh-kotlin/src/commonTest/kotlin/io/zenoh/ConnectivityTest.kt` | CREATE |

---

## Verification

1. Build Rust JNI: `cd zenoh-jni && cargo build`
2. Run Kotlin tests: `./gradlew test` — `ConnectivityTest` should pass all test cases

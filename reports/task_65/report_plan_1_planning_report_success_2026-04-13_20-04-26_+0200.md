# Plan: Implement Connectivity API for zenoh-kotlin

## Context
Zenoh 1.8.0 exposes `session.info().transport_events_listener()` (unstable API) that allows subscribing to transport-level connectivity events — fired when a session opens or closes a connection to another zenoh node (peer or router). The zenoh-kotlin binding does not yet expose this API. This task adds a `declareTransportEventsListener()` method to `SessionInfo` plus all supporting layers (JNI callback interface, JNI Kotlin bridge, Rust JNI implementation).

**Closest analog:** The `MatchingListener` pattern (no key expression, callback-based, pointer stored as `Arc`, freed on close) combined with the three-overload style from `Liveliness` (callback, handler, channel).

---

## Files to Create

### 1. `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/TransportEvent.kt`
Data class carrying a single connectivity event:
```
data class TransportEvent(val kind: SampleKind, val zid: ZenohId, val whatAmI: WhatAmI)
```
- `kind = SampleKind.PUT` → connection opened; `SampleKind.DELETE` → connection closed
- `zid` is the ZenohId of the remote node
- `whatAmI` identifies whether it is a Router, Peer, or Client

### 2. `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/TransportEventsListener.kt`
Public Kotlin wrapper (mirrors `MatchingListener` / `Subscriber<R>` patterns):
```
class TransportEventsListener<R>(val receiver: R, private val jniListener: JNITransportEventsListener) : AutoCloseable {
    override fun close() { jniListener.close() }
}
```

### 3. `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNITransportEventsListener.kt`
Internal class holding the raw Rust pointer (identical structure to `JNIMatchingListener`):
```
internal class JNITransportEventsListener(private val ptr: Long) {
    fun close() { freePtrViaJNI(ptr) }
    private external fun freePtrViaJNI(ptr: Long)
}
```
The `freePtrViaJNI` JNI name resolves to `Java_io_zenoh_jni_JNITransportEventsListener_freePtrViaJNI`.

### 4. `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/JNITransportCallback.kt`
New functional interface for the JNI callback:
```
internal fun interface JNITransportCallback {
    fun run(kind: Int, zid: ByteArray, whatAmI: Int)
}
```
- `kind`: 0 = PUT (opened), 1 = DELETE (closed) — matches `SampleKind.ordinal`
- `zid`: little-endian bytes of the remote `ZenohId`
- `whatAmI`: Router=1, Peer=2, Client=4 — matches Kotlin `WhatAmI.value`

### 5. `zenoh-jni/src/connectivity.rs`
Two JNI functions:

**`Java_io_zenoh_jni_JNISessionInfo_declareTransportEventsListenerViaJNI`**
- Parameters: `session_ptr: *const Session`, `callback: JObject`, `history: jboolean`, `on_close: JObject`
- Returns: `*const TransportEventsListener<()>` (null on failure, exception thrown)
- Implementation:
  1. Use `OwnedObject::from_raw(session_ptr)` (borrows without transferring ownership)
  2. Get `java_vm`, `callback_global_ref`, `on_close_global_ref` / `load_on_close`
  3. Call `session.info().transport_events_listener().history(history != 0).callback(move |event| { ... }).wait()?`
  4. Inside callback: attach thread as daemon, call `callback_global_ref.run(kind as jint, zid_bytes, whatami as jint)` via JNI with signature `"(I[BI)V"`
  5. Return `Arc::into_raw(Arc::new(listener))`

**`Java_io_zenoh_jni_JNITransportEventsListener_freePtrViaJNI`**
- Parameter: `ptr: *const TransportEventsListener<()>`
- Implementation: `Arc::from_raw(ptr)` — drops the Arc, undeclaring the listener

---

## Files to Modify

### 6. `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionInfo.kt`
Add three overloaded `declareTransportEventsListener()` methods (following the same three-overload pattern as `Liveliness.declareSubscriber()`):
- `declareTransportEventsListener(callback, history, onClose)` → `Result<TransportEventsListener<Unit>>`
- `declareTransportEventsListener(handler, history, onClose)` → `Result<TransportEventsListener<R>>`
- `declareTransportEventsListener(channel, history, onClose)` → `Result<TransportEventsListener<Channel<TransportEvent>>>`

Each variant accesses `session.jniSession` (accessible since `SessionInfo` is in the same Kotlin module) and calls through a new `JNISessionInfo` internal object.

### 7. `JNISessionInfo` bridge (new `internal object` — can live in its own file or at top of `SessionInfo.kt`)
Bridges `SessionInfo` to the native layer:
```
internal object JNISessionInfo {
    fun <R> declareTransportEventsListener(
        jniSession: JNISession,
        callback: Callback<TransportEvent>,
        receiver: R,
        history: Boolean,
        onClose: () -> Unit
    ): Result<TransportEventsListener<R>>
}
```
Builds the `JNITransportCallback`, calls `declareTransportEventsListenerViaJNI(ptr, callback, history, onClose)`, wraps result in `TransportEventsListener(receiver, JNITransportEventsListener(ptr))`.

### 8. `zenoh-jni/src/lib.rs`
Add `mod connectivity;` alongside `mod liveliness`.

---

## New Example

### `examples/src/main/kotlin/io.zenoh/ZConnectivity.kt`
Demonstrates subscribing to transport events:
- Open session
- Call `session.info().declareTransportEventsListener(callback = { event -> println("...") }, history = true)`
- Keep running until interrupted, then close listener

---

## Key Design Decisions
- **Extended `SessionInfo`** rather than a new `connectivity()` accessor — mirrors the Rust API placement (`session.info().transport_events_listener()`) and avoids extra surface area.
- **Callback-only JNI layer** — the Rust side always uses `.callback()` since the threading model requires JNI; channel/handler support is composed on the Kotlin side exactly like liveliness.
- **`OwnedObject::from_raw`** for the session pointer — consistent with liveliness.rs; does not transfer ownership.
- **`Arc<TransportEventsListener<()>>`** for the Rust side — same as `Arc<Subscriber<()>>` in liveliness; dropped via `freePtrViaJNI`.

---

## Verification
1. **Build:** `./gradlew :zenoh-kotlin:compileKotlinJvm` + `cargo build` inside `zenoh-jni/`
2. **Integration test:** Run `ZConnectivity` example with a second peer; verify PUT event fires on connect, DELETE on disconnect.
3. **History flag:** Open listener with `history = true` while already connected; verify existing connection event delivered immediately.
4. **Cleanup:** Call `listener.close()`, verify no further events and no memory leak.

# Plan: Implement Connectivity API for zenoh-kotlin

## Context

GitHub issue #647 asks to implement the connectivity API for zenoh-kotlin, mirroring the zenoh-go
implementation. Zenoh 1.8 exposes `session.info().transports()`, `.transport_events_listener()`,
`.links()`, and `.link_events_listener()` as unstable APIs. The Kotlin binding currently has no
connectivity API. Previous plan drafts were rejected for: (1) only covering transport events while
omitting links/link events and the snapshot queries, (2) flattening `Transport`/`Link` fields into
the event type instead of using a snapshot type, (3) not following the repo's `SessionDeclaration`
lifecycle pattern, and (4) incorrect assumption about JNI access in `SessionInfo`.

---

## Closest Analog

**`MatchingListener`** (lifecycle pattern) + **`Liveliness.declareSubscriber`** (three-overload
callback/handler/channel) + **`session.rs`** `getPeersZidViaJNI` (session pointer management for
synchronous info queries).

---

## Architecture

The full connectivity API has four entry points on `SessionInfo`:
- `transports()` → snapshot list
- `declareTransportEventsListener(...)` → long-lived listener
- `links()` → snapshot list
- `declareLinkEventsListener(...)` → long-lived listener

All are `@Unstable`. Data types (`Transport`, `Link`, `TransportEvent`, `LinkEvent`) implement
`ZenohType` so the generic `Callback<T>` / `Handler<T, R>` / `ChannelHandler<T>` abstractions work
without custom callback interfaces.

---

## Files to Create

### 1. Public Kotlin types — `io.zenoh.session` package

**`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/Transport.kt`**
- `@Unstable data class Transport(val zid: ZenohId, val whatAmI: WhatAmI, val isQos: Boolean, val isMulticast: Boolean) : ZenohType`

**`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/Link.kt`**
- `@Unstable data class Link(val zid: ZenohId, val src: String, val dst: String, val group: String?, val mtu: Int, val isStreamed: Boolean, val interfaces: List<String>) : ZenohType`
- `src`/`dst`/`group` are Locators serialized as strings (Rust `Locator::to_string()`)

**`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/TransportEvent.kt`**
- `@Unstable data class TransportEvent(val kind: SampleKind, val transport: Transport) : ZenohType`

**`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/LinkEvent.kt`**
- `@Unstable data class LinkEvent(val kind: SampleKind, val link: Link) : ZenohType`

**`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/TransportEventsListener.kt`**
- `@Unstable class TransportEventsListener internal constructor(private var jniListener: JNITransportEventsListener?) : SessionDeclaration, AutoCloseable`
- `isValid()`, `undeclare()` (closes JNI handle + nullifies), `close()` delegates to `undeclare()`, `finalize()` as safety net

**`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/LinkEventsListener.kt`**
- Same pattern as `TransportEventsListener` but holds `JNILinkEventsListener`

### 2. Internal JNI wrappers — `io.zenoh.jni` package

**`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNITransportEventsListener.kt`**
```kotlin
internal class JNITransportEventsListener(private val ptr: Long) {
    fun close() { freePtrViaJNI(ptr) }
    private external fun freePtrViaJNI(ptr: Long)
}
```
JNI name: `Java_io_zenoh_jni_JNITransportEventsListener_freePtrViaJNI`

**`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNILinkEventsListener.kt`**
- Same pattern

### 3. Internal JNI callback interfaces — `io.zenoh.jni.callbacks` package

**`JNITransportSnapshotCallback.kt`** (for `getTransports()`)
```kotlin
internal fun interface JNITransportSnapshotCallback {
    fun run(zidBytes: ByteArray, whatAmI: Int, isQos: Boolean, isMulticast: Boolean)
}
```

**`JNITransportEventCallback.kt`** (for `declareTransportEventsListener()`)
```kotlin
internal fun interface JNITransportEventCallback {
    fun run(kind: Int, zidBytes: ByteArray, whatAmI: Int, isQos: Boolean, isMulticast: Boolean)
}
```

**`JNILinkSnapshotCallback.kt`** (for `getLinks()`)
```kotlin
internal fun interface JNILinkSnapshotCallback {
    fun run(zidBytes: ByteArray, src: String, dst: String, group: String?, mtu: Int, isStreamed: Boolean, interfaces: Array<String>)
}
```

**`JNILinkEventCallback.kt`** (for `declareLinkEventsListener()`)
```kotlin
internal fun interface JNILinkEventCallback {
    fun run(kind: Int, zidBytes: ByteArray, src: String, dst: String, group: String?, mtu: Int, isStreamed: Boolean, interfaces: Array<String>)
}
```

### 4. Rust module

**`zenoh-jni/src/connectivity.rs`** — 6 `#[no_mangle] pub extern "C"` functions:

**Snapshot functions (synchronous, no async task)**

`Java_io_zenoh_jni_JNISession_getTransportsViaJNI(session_ptr, callback: JObject)`
- `Arc::from_raw(session_ptr)` + `mem::forget` (same pattern as `getPeersZidViaJNI`)
- `session.info().transports().wait()` → iterate transports
- For each: `env.call_method(callback, "run", "([BIZz)V", &[zid_bytes, whatami, is_qos, is_multicast])`

`Java_io_zenoh_jni_JNISession_getLinksViaJNI(session_ptr, callback: JObject)`
- Same pattern; call `session.info().links().wait()` → iterate; pass each link's fields to callback
- String fields via `env.new_string(locator.to_string())`, nullable group via `JObject::null()` or string

**Event listener functions (async, return raw pointer)**

`Java_io_zenoh_jni_JNISession_declareTransportEventsListenerViaJNI(session_ptr, callback, history, on_close) -> *const TransportEventsListener<()>`
- `OwnedObject::from_raw(session_ptr)` (borrow without transferring ownership)
- `get_java_vm`, `get_callback_global_ref` for callback and on_close, `load_on_close`
- `session.info().transport_events_listener().history(history != 0).callback(move |event| { ... }).wait()?`
- Inside callback: `java_vm.attach_current_thread_as_daemon()` → `env.call_method(callback_ref, "run", "(I[BIZz)V", &[kind, zid, whatami, is_qos, is_multicast])`
- Return `Arc::into_raw(Arc::new(listener))`

`Java_io_zenoh_jni_JNITransportEventsListener_freePtrViaJNI(ptr: *const TransportEventsListener<()>)`
- `Arc::from_raw(ptr)` — drops, undeclaring the listener

`Java_io_zenoh_jni_JNISession_declareLinkEventsListenerViaJNI(session_ptr, callback, history, on_close) -> *const LinkEventsListener<()>`
- Same as transport variant but for links; callback passes `kind`, `zid`, `src`, `dst`, `group` (nullable), `mtu`, `is_streamed`, `interfaces` (JObjectArray or serialized)

`Java_io_zenoh_jni_JNILinkEventsListener_freePtrViaJNI(ptr: *const LinkEventsListener<()>)`
- Same pattern

### 5. Example

**`examples/src/main/kotlin/io.zenoh/ZConnectivity.kt`**
- Open session
- Print existing transports via `session.info().transports()`
- Declare transport events listener and link events listener, print events
- Keep alive until Ctrl+C, then close listeners

---

## Files to Modify

### `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionInfo.kt`

Add 8 public `@Unstable` methods delegating through `session.*`:

```
@Unstable
fun transports(): Result<List<Transport>> = session.getTransports()

@Unstable
fun declareTransportEventsListener(
    callback: Callback<TransportEvent>,
    history: Boolean = false,
    onClose: (() -> Unit)? = null
): Result<TransportEventsListener>

@Unstable
fun <R> declareTransportEventsListener(
    handler: Handler<TransportEvent, R>,
    history: Boolean = false,
    onClose: (() -> Unit)? = null
): Result<TransportEventsListener>

@Unstable
fun declareTransportEventsListener(
    channel: Channel<TransportEvent>,
    history: Boolean = false,
    onClose: (() -> Unit)? = null
): Result<TransportEventsListener>

// Same 4 for links
@Unstable fun links(): Result<List<Link>> = session.getLinks()
// + 3 overloads for declareLinkEventsListener
```

Handler and channel overloads build a `Callback<T>` from the handler/channel, delegating to the
callback overload. `ChannelHandler<T>` (already exists, generic over `T: ZenohType`) works directly.

### `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt`

Add `internal` methods matching the SessionInfo surface:

```kotlin
internal fun getTransports(): Result<List<Transport>> =
    jniSession?.getTransports() ?: Result.failure(sessionClosedException)

internal fun getLinks(): Result<List<Link>> =
    jniSession?.getLinks() ?: Result.failure(sessionClosedException)

internal fun declareTransportEventsListener(
    callback: Callback<TransportEvent>, history: Boolean, onClose: () -> Unit
): Result<TransportEventsListener> = runCatching {
    val jni = jniSession ?: throw sessionClosedException
    val listener = jni.declareTransportEventsListener(...)
    strongDeclarations.add(listener)
    listener
}

internal fun declareLinkEventsListener(...): Result<LinkEventsListener>  // same pattern
```

Listeners go into `strongDeclarations` (consistent with Subscriber/Queryable — they keep running
and should be undeclared on session close).

### `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`

Add 4 methods + 6 external function declarations:

```kotlin
fun getTransports(): Result<List<Transport>> = runCatching {
    val transports = mutableListOf<Transport>()
    val cb = JNITransportSnapshotCallback { zidBytes, whatAmI, isQos, isMulticast ->
        transports.add(Transport(ZenohId(zidBytes), WhatAmI.fromInt(whatAmI), isQos, isMulticast))
    }
    getTransportsViaJNI(sessionPtr.get(), cb)
    transports
}

fun getLinks(): Result<List<Link>> = runCatching { /* similar */ }

fun declareTransportEventsListener(
    callback: JNITransportEventCallback, history: Boolean, onClose: () -> Unit
): TransportEventsListener {
    val ptr = declareTransportEventsListenerViaJNI(sessionPtr.get(), callback, history, onClose)
    return TransportEventsListener(JNITransportEventsListener(ptr))
}

fun declareLinkEventsListener(...): LinkEventsListener  // same pattern

private external fun getTransportsViaJNI(sessionPtr: Long, callback: JNITransportSnapshotCallback)
private external fun getLinksViaJNI(sessionPtr: Long, callback: JNILinkSnapshotCallback)
private external fun declareTransportEventsListenerViaJNI(
    sessionPtr: Long, callback: JNITransportEventCallback, history: Boolean, onClose: JNIOnCloseCallback
): Long
private external fun declareLinkEventsListenerViaJNI(
    sessionPtr: Long, callback: JNILinkEventCallback, history: Boolean, onClose: JNIOnCloseCallback
): Long
```

### `zenoh-jni/src/lib.rs`

Add `mod connectivity;` alongside `mod liveliness;`.

---

## Key Design Decisions

1. **Full API surface**: Implements all four connectivity entry points (transports snapshot, transport
   events, links snapshot, link events) as required by the issue and upstream Rust API.

2. **`Transport` and `Link` as snapshot types**: `TransportEvent` contains `Transport`; `LinkEvent`
   contains `Link`. Matches upstream and the zenoh-go analog; shares value types between snapshots
   and events.

3. **`ZenohType` marker**: Both `TransportEvent` and `LinkEvent` implement `ZenohType`, enabling use
   of the existing generic `Callback<T>`, `Handler<T, R>`, and `ChannelHandler<T>` abstractions
   without custom callback interfaces.

4. **Session lifecycle**: Listeners added to `strongDeclarations` in Session.kt — automatically
   undeclared on `session.close()`, consistent with `Subscriber` and `Queryable`.

5. **Delegation chain**: `SessionInfo` → `Session` (internal methods) → `JNISession` → JNI. Matches
   exactly how `zid()`, `peersZid()`, `routersZid()` are structured.

6. **Callback approach for snapshots**: `getTransportsViaJNI` and `getLinksViaJNI` receive a Kotlin
   callback object and call it synchronously for each item. Kotlin builds the list. Avoids
   constructing complex Java objects from Rust.

7. **`@Unstable`**: All new types, methods, and listener classes are annotated `@Unstable`.

---

## Verification

1. **Build**: `./gradlew :zenoh-kotlin:compileKotlinJvm` + `cargo build` inside `zenoh-jni/`
2. **Snapshot query**: Call `session.info().transports()` — returns current transports.
3. **Transport event listener**: `history = true` while connected → existing connection events
   delivered; open new peer → PUT event; close it → DELETE event.
4. **Link events**: Same as transport events for `declareLinkEventsListener`.
5. **Listener lifecycle**: `listener.undeclare()` → no further events; second `undeclare()` is no-op.
6. **Session close**: Without explicit `listener.close()`, call `session.close()` — listeners are
   undeclared via `strongDeclarations`.
7. **Example**: Run `ZConnectivity` against a second zenoh peer.

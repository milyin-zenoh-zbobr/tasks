Here is the implementation plan:

## Connectivity API for zenoh-kotlin

### Background
Zenoh 1.8.0 exposes `session.info().transport_events_listener()` (unstable feature, already enabled via `features = ["unstable", "internal"]` in `Cargo.toml`). This fires `TransportEvent` each time a connection to another zenoh node opens (`SampleKind.PUT`) or closes (`SampleKind.DELETE`), carrying the remote node's `ZenohId` and `WhatAmI`. The zenoh-kotlin binding has no Kotlin API for this yet.

### New files to create

| File | Purpose |
|---|---|
| `...session/TransportEvent.kt` | `data class TransportEvent(kind, zid, whatAmI)` |
| `...session/TransportEventsListener.kt` | Public wrapper `class TransportEventsListener<R>(receiver, jniListener)` with `close()` |
| `...jni/JNITransportEventsListener.kt` | Internal class holding raw Rust `*const TransportEventsListener<()>` pointer with `freePtrViaJNI` |
| `...jni/callbacks/JNITransportCallback.kt` | `fun interface JNITransportCallback { fun run(kind: Int, zid: ByteArray, whatAmI: Int) }` |
| `zenoh-jni/src/connectivity.rs` | Rust JNI: `declare…ViaJNI` + `freePtrViaJNI` |
| `examples/…/ZConnectivity.kt` | Demo example |

### Files to modify

- **`SessionInfo.kt`** — add 3 overloads of `declareTransportEventsListener()` (callback / handler / channel), plus a new `internal object JNISessionInfo` bridge
- **`zenoh-jni/src/lib.rs`** — add `mod connectivity;`

### Design rationale
- Extended `SessionInfo` (not a new `connectivity()` on `Session`) to mirror the Rust API placement exactly.
- Rust side always uses `.callback()` builder; channel/handler variants are composed on the Kotlin side — same approach as `Liveliness`.
- Rust pointer lifecycle: `Arc::into_raw` on declare, `Arc::from_raw` on free — identical to `MatchingListener` / `Subscriber`.
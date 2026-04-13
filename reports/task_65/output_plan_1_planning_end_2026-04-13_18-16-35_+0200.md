Here is the implementation plan I've designed:

## Plan: Connectivity API for zenoh-kotlin

The zenoh 1.8.0 Rust dependency already has `unstable` + `internal` features enabled, exposing the full connectivity API. No existing implementation exists in the work branch — only a whitespace fix. The implementation follows established patterns in the codebase.

### New files to create (14)

**Kotlin data types** (`io.zenoh.session.connectivity` package, all `@Unstable`):
- `Transport` — zid, whatAmI, isQos, isMulticast
- `Link` — zid, src/dst/group (Strings), mtu, isStreamed, interfaces, authIdentifier, `priorities: Pair<Int,Int>?`, `reliability: Reliability?`
- `TransportEvent`, `LinkEvent` — kind + payload
- `TransportEventsListener`, `LinkEventsListener` — mirror the `MatchingListener` pattern (hold JNI ptr, undeclare on close)

**JNI handles** (`io.zenoh.jni`): `JNITransportEventsListener`, `JNILinkEventsListener` — mirror `JNIMatchingListener` (hold `ptr: Long`, `freePtrViaJNI`)

**JNI callbacks** (`io.zenoh.jni.callbacks`): 4 `fun interface` types — 2 for synchronous snapshots (TransportCallback, LinkCallback), 2 for async events (TransportEventCallback, LinkEventCallback)

**`JNIConnectivity.kt`** — internal object with 4 methods + 4 `external fun` declarations delegating to Rust

**`zenoh-jni/src/connectivity.rs`** — 6 JNI functions: `getTransports`, `getLinks` (synchronous, iterate and call JVM callback), `declareTransportEventsListener`, `declareLinkEventsListener` (async, use `get_java_vm`/`callback_global_ref` closure pattern), plus 2 `freePtrViaJNI` functions

### Files to modify (2)

- `SessionInfo.kt` — add 4 `@Unstable` methods delegating to `JNIConnectivity` (same pattern as `Liveliness.kt`)
- `zenoh-jni/src/lib.rs` — add `mod connectivity;`

### Key design decisions
- Rust side uses `session.info().transports().wait()` / `session.info().transport_events_listener().history(h).callback(closure).wait()` etc.
- Transport filter for `getLinks`/`declareLinkEventsListener` passed as primitive fields + boolean flag
- `priorities` exposed as `Pair<Int,Int>?` (raw u8 values that can include 0=Control)
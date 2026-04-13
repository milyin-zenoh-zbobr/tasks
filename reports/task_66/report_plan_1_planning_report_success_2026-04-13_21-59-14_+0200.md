# Connectivity API for zenoh-kotlin — Implementation Plan

## Context

The upstream zenoh Rust library added an unstable connectivity API that exposes network-level introspection: snapshot queries for active transports and links, and listener subscriptions for transport and link lifecycle events. The Go binding (PR #17) already implements this. This task brings the same API to zenoh-kotlin.

**Previous plan issues** (from adversarial review):
1. Used `Callback<TransportEvent>`/`Callback<LinkEvent>` — wrong since `ZenohType` hierarchy only covers `Sample`/`Reply`/`Query`
2. Only provided callback overloads — missing handler and channel overloads
3. Missing `history` option for listeners
4. Missing transport filter for `links()` snapshot and link event listeners
5. Background listener used manual Arc state storage — wrong, must use `.background().wait()` in Rust
6. `interfaces: Vec<String>` marshalled as delimiter-joined string — should use Java String array

## Closest Analog

`AdvancedSubscriber.declareSampleMissListener` + `SampleMissCallback`/`SampleMissHandler<R>`/`SampleMissChannelHandler` pattern — dedicated callback/handler/channel types, 6 overloads (3 foreground + 3 background), history option, delegated through JNISession → Session → SessionInfo.

## Upstream API Used (all `#[zenoh_macros::unstable]`)

- `session.info().transports().wait()` → Iterator<Transport>
- `session.info().links()` → LinksBuilder → `.transport(t)` (optional) → `.wait()` → Iterator<Link>
- `session.info().transport_events_listener()` → builder → `.history(bool)` → `.callback(f)` / `.background()` → `.wait()`
- `session.info().link_events_listener()` → builder → `.history(bool)` → `.transport(t)` (optional) → `.callback(f)` / `.background()` → `.wait()`

Transport fields: zid, whatami, is_qos, is_multicast, is_shm
Link fields: zid, src (Locator→String), dst (Locator→String), group (Option<Locator>→String?), mtu (u16→Int), is_streamed, interfaces (Vec<String>→List<String>), auth_identifier (Option<String>), priorities (Option<(u8,u8)>→priorityMin?/priorityMax?), reliability (Option<Reliability>)

## Implementation Steps

### 1. New data classes — `io.zenoh.connectivity` package

- `Transport.kt` (@Unstable data class): zid: ZenohId, whatAmI: WhatAmI, isQos: Boolean, isMulticast: Boolean, isShm: Boolean
- `Link.kt` (@Unstable data class): zid, src, dst, group?, mtu, isStreamed, interfaces, authIdentifier?, priorityMin?, priorityMax?, reliability? (reuse io.zenoh.qos.Reliability)
- `TransportEvent.kt` (@Unstable data class): kind: SampleKind, transport: Transport
- `LinkEvent.kt` (@Unstable data class): kind: SampleKind, link: Link
- `TransportEventsListener.kt` (@Unstable class): SessionDeclaration + AutoCloseable wrapping JNITransportEventsListener? — exact MatchingListener.kt pattern
- `LinkEventsListener.kt` (@Unstable class): same pattern wrapping JNILinkEventsListener?

### 2. Callback/Handler types — `io.zenoh.handlers` package

Follow SampleMissCallback/SampleMissHandler/SampleMissChannelHandler pattern exactly:
- `TransportEventsCallback` — @Unstable fun interface { fun run(event: TransportEvent) }
- `TransportEventsHandler<R>` — @Unstable interface with handle(), receiver(), onClose()
- `TransportEventsChannelHandler` — internal class wrapping Channel<TransportEvent>
- `LinkEventsCallback`, `LinkEventsHandler<R>`, `LinkEventsChannelHandler` — same

### 3. JNI callback interfaces — `io.zenoh.jni.callbacks` package

JNITransportEventsCallback: fun run(kind: Int, zidBytes: ByteArray, whatAmI: Int, isQos: Boolean, isMulticast: Boolean, isShm: Boolean)

JNILinkEventsCallback: fun run(kind: Int, zidBytes: ByteArray, src: String, dst: String, group: String?, mtu: Int, isStreamed: Boolean, interfaces: Array<String>, authIdentifier: String?, priorityMin: Int, priorityMax: Int, reliability: Int)
  - priorityMin/priorityMax/reliability use -1 sentinel for None; interfaces is proper Java String[] (not delimiter-joined)

### 4. JNI listener wrappers — `io.zenoh.jni` package

JNITransportEventsListener.kt and JNILinkEventsListener.kt: hold ptr: Long; close() calls freePtrViaJNI(ptr) — same as JNIMatchingListener.kt

### 5. Extend JNISession.kt

New external declarations:
- getTransportsViaJNI(ptr: Long): List<Any>  — ArrayList of Object[5] per transport
- getLinksViaJNI(ptr: Long, transportZid: ByteArray?): List<Any>  — ArrayList of Object[] per link
- declareTransportEventsListenerViaJNI(ptr, callback, onClose, history): Long
- declareBackgroundTransportEventsListenerViaJNI(ptr, callback, onClose, history)
- declareLinkEventsListenerViaJNI(ptr, callback, onClose, history, transportZid: ByteArray?): Long
- declareBackgroundLinkEventsListenerViaJNI(ptr, callback, onClose, history, transportZid: ByteArray?)

Transport filter design: pass `ByteArray?` from `transport.zid.bytes`. Rust side calls `session.info().transports().find(|t| t.zid().to_le_bytes() == filter)` to recover the Transport object for the builder.

New Kotlin wrappers in JNISession that wrap external calls and construct Kotlin objects from returned data.

### 6. Extend Session.kt (internal delegation)

Add internal methods that delegate from SessionInfo calls to JNISession methods — same pattern as existing getPeersId()/getRoutersId().

### 7. Extend SessionInfo.kt (public API)

Transport snapshot: `@Unstable fun transports(): Result<List<Transport>>`

Transport event listeners — 6 overloads (callback/handler/channel × foreground/background), each with `history: Boolean = false`:
- `fun declareTransportEventsListener(callback: TransportEventsCallback, onClose: (() -> Unit)? = null, history: Boolean = false): Result<TransportEventsListener>`
- `fun <R> declareTransportEventsListener(handler: TransportEventsHandler<R>, ...): Result<TransportEventsListener>`
- `fun <R> declareTransportEventsListener(channel: Channel<TransportEvent>, ...): Result<TransportEventsListener>`
- 3 background variants returning Result<Unit>

Link snapshot: `@Unstable fun links(transport: Transport? = null): Result<List<Link>>`

Link event listeners — 6 overloads, each with `history: Boolean = false` and `transport: Transport? = null`.

Handler→callback conversion follows AdvancedPublisher.kt pattern (val callback = TransportEventsCallback { event -> handler.handle(event) }).

### 8. New Rust file: `zenoh-jni/src/connectivity.rs`

Register in lib.rs: `mod connectivity;`

getTransportsViaJNI:
- session.info().transports().wait() [needs #[cfg(feature = "unstable")]]
- Build Java ArrayList; each element Object[5]: [ByteArray(zid 16 bytes), jint(whatami), jboolean(isQos), jboolean(isMulticast), jboolean(isShm)]
- std::mem::forget(session_arc) pattern from session.rs

getLinksViaJNI:
- If transportZid not null: find matching Transport via session.info().transports(), then session.info().links().transport(t).wait(); else session.info().links().wait()
- Each element Object[]: [ByteArray(zid), String(src), String(dst), String|null(group), jint(mtu), jboolean(is_streamed), String[](interfaces), String|null(authId), jint(pMin or -1), jint(pMax or -1), jint(reliability or -1)]

declareTransportEventsListenerViaJNI:
- Build Rust callback calling JNITransportEventsCallback.run() with GlobalRef + JavaVM + attach_current_thread_as_daemon (same pattern as matching_listener.rs)
- session.info().transport_events_listener().history(history).callback(cb).wait()
- Return Arc::into_raw(Arc::new(listener))

declareBackgroundTransportEventsListenerViaJNI:
- Same but chain .background() before .wait(), return void

declareLinkEventsListenerViaJNI:
- If transportZid passed: find Transport, chain .transport(t)
- Callback passes all Link fields; interfaces as Java String[] via env.new_object_array
- Same foreground/background variants

JNITransportEventsListener_freePtrViaJNI and JNILinkEventsListener_freePtrViaJNI:
- Arc::from_raw(ptr) to drop (same as matching_listener.rs)

### 9. Test file: ConnectivityTest.kt

- testTransportsList: two connected sessions, assert transports() returns list with peer's ZenohId
- testLinksListNoFilter: two connected sessions, assert links() non-empty
- testLinksListWithFilter: use Transport from transports() to filter links(transport) — result is subset
- testTransportEventsListenerPutDelete: subscribe, connect second session, assert PUT; disconnect, assert DELETE
- testTransportEventsHistory: open listener with history=true after connecting peer, assert history event delivered
- testLinkEventsListenerPutDelete: same for links
- testLinkEventsListenerWithTransportFilter: filter link events by specific transport
- testBackgroundListeners: background variants fire correctly

## Critical Files

| File | Action |
|------|--------|
| zenoh-jni/src/connectivity.rs | CREATE |
| zenoh-jni/src/lib.rs | ADD mod connectivity |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/Transport.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/Link.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/TransportEvent.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/LinkEvent.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/TransportEventsListener.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/LinkEventsListener.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/TransportEventsCallback.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/TransportEventsHandler.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/TransportEventsChannelHandler.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/LinkEventsCallback.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/LinkEventsHandler.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/LinkEventsChannelHandler.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/JNITransportEventsCallback.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/JNILinkEventsCallback.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNITransportEventsListener.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNILinkEventsListener.kt | CREATE |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt | EXTEND |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionInfo.kt | EXTEND |
| zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt | EXTEND (internal delegation) |
| zenoh-kotlin/src/commonTest/kotlin/io/zenoh/ConnectivityTest.kt | CREATE |

## Verification

1. `cd zenoh-jni && cargo build --features unstable`
2. `./gradlew test --tests "io.zenoh.ConnectivityTest"`
3. `./gradlew test` (full regression check)

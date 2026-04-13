I do **not** think this plan is ready for implementation yet.

The high-level 3-layer shape is reasonable, but there are several concrete gaps that will either make the API incomplete or make the implementation fail to match existing repo conventions.

## Blocking issues

1. **`declareLinkEventsListener` is missing the transport filter entirely**
   - Upstream Rust supports this: `SessionInfo::link_events_listener()` returns a builder with `.transport(transport)` in `zenoh/src/api/builders/info_links.rs`.
   - The Go reference also supports it in both sync and async forms (`InfoLinksOptions.Transport`, `LinkEventsListenerOptions.Transport` in `zenoh-go/zenoh/link.go`).
   - The current plan only adds `links(transport: Transport? = null)` but the listener API has no transport parameter, and the Rust section only describes `declareLinkEventsListener(sessionPtr, callback, history, onClose)`.
   - That means the proposed API does **not** implement the full connectivity surface that exists upstream.

2. **The listener event types need to satisfy Kotlin’s existing handler/callback type bounds**
   - In this repo, `Callback<T>` and `Handler<T, R>` are defined as `T : ZenohType` (`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/Callback.kt`, `Handler.kt`).
   - The plan uses `Callback<TransportEvent>` and `Callback<LinkEvent>`, but it never states that `TransportEvent` / `LinkEvent` implement `ZenohType`.
   - As written, that API will not compile.

3. **Session lifecycle / cleanup wiring is missing from the plan**
   - `Session.close()` only undeclares objects that were registered in `strongDeclarations` / `weakDeclarations` (`Session.kt`).
   - Session-scoped long-lived declarations (subscribers, queryables, etc.) are added there when created.
   - The plan only mentions changes to `SessionInfo.kt` and JNI files, but nothing about `Session.kt` bookkeeping for the new listener objects.
   - These connectivity listeners are session-scoped, so if they are not registered, `Session.close()` will not undeclare them before dropping `JNISession`. That is a real lifecycle hole.

4. **The transport-filter design is internally inconsistent and needs to be made explicit**
   - The plan says the Kotlin `Transport` is a pure snapshot and also says it wants to avoid reconstructing a Rust `Transport` from Kotlin.
   - But then the Rust section says `getLinksViaJNI` will reconstruct a `Transport` from fields when filtering.
   - Upstream Rust already provides the right mechanism for this (`Transport::new_from_fields(...)` in `zenoh/src/api/info.rs`), and the Go binding does the same conceptually with `Transport.toCPtr()` in `zenoh-go/zenoh/transport.go`.
   - This needs one coherent design, because both `links(transport)` **and** filtered link-events listeners depend on it.

5. **The plan has no test strategy**
   - This repo already has session-info tests in `zenoh-kotlin/src/commonTest/kotlin/io/zenoh/SessionInfoTest.kt` and lifecycle tests in `SessionTest.kt`.
   - The Go reference has extensive connectivity coverage in `zenoh-go/tests/connectivity_test.go`: transports, links, links filtered by transport, transport events, link events, history, undeclare, empty lists, and background listeners.
   - None of that is reflected in the Kotlin plan. Given the amount of callback/lifecycle logic here, tests are not optional.

## Important non-blocking concerns

1. **API surface is probably too narrow for Kotlin conventions**
   - Existing Kotlin streaming APIs usually expose callback / handler / channel overloads (`Session`, `Liveliness`, `AdvancedPublisher`, `AdvancedSubscriber`).
   - The plan only specifies callback-based listener declaration methods.
   - That may be acceptable if intentionally scoped down, but it should be explicit because it diverges from the prevailing API style.

2. **Background listeners are not addressed**
   - Upstream Rust builders and the Go binding both support background transport/link event listeners.
   - The plan only covers explicit listener handles.
   - If background listeners are intentionally out of scope, that should be stated. Otherwise the implementation will lag the upstream surface.

3. **`JNIConnectivity` may be a less consistent placement than extending `JNISession`**
   - Existing session-info JNI methods (`zid`, `peersZid`, `routersZid`) live on `JNISession` and are reached through `Session -> JNISession -> SessionInfo`.
   - A separate `JNIConnectivity` object is possible, but it is not obviously aligned with the current structure and should be justified if kept.

## What I would require in the revised plan

1. Add the missing **transport filter** to link-event listeners end-to-end (public Kotlin API, JNI bridge, Rust JNI layer).
2. State explicitly that `TransportEvent` and `LinkEvent` implement `ZenohType`.
3. Add the missing **session lifecycle wiring** so connectivity listeners are undeclared during `Session.close()`.
4. Replace the contradictory filter story with one clear mechanism, ideally mirroring upstream/Go: snapshot transport in Kotlin plus explicit native reconstruction for filter options.
5. Add a concrete **test plan** covering at least:
   - transports list
   - links list
   - links filtered by transport
   - transport events listener
   - link events listener
   - history=true behavior
   - undeclare / close behavior
   - empty result cases

Once those are addressed, the overall direction should be implementable.
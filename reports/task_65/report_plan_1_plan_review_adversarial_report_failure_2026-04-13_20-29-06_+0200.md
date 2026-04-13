I reviewed the plan against the current zenoh-kotlin codebase, the Rust 1.8 session API surface available through the JNI crate in this repo, and the public upstream connectivity docs.

## Verdict
The plan is **not ready for implementation**. The main problem is scope: it still treats connectivity as only transport events, while upstream connectivity covers both **transports** and **links**, including both **snapshots** and **event listeners**. There are also a couple of important mismatches with existing zenoh-kotlin conventions that should be fixed before coding starts.

## What I verified locally
- `zenoh-jni/Cargo.toml` already depends on `zenoh = 1.8.0` with `unstable` enabled, so the native crate version is the one that exposes the connectivity API family.
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionInfo.kt` is currently the right place to extend; it already holds session information methods.
- Existing listener/declaration wrappers in Kotlin (`MatchingListener`, `SampleMissListener`, `Subscriber`, etc.) consistently follow the repo’s declaration lifecycle conventions.
- `Session.close()` undeclares tracked `SessionDeclaration`s, so lifecycle integration is a real architectural concern, not a cosmetic one.

## Blocking issues

### 1. The plan is still under-scoped: connectivity is not just transport events
Upstream connectivity includes all of the following unstable surfaces under session info:
- `transports()`
- `transport_events_listener()`
- `links()`
- `link_events_listener()`

The current plan only describes `declareTransportEventsListener()` plus transport-event-related types. That is not enough for the connectivity API as exposed upstream, and it directly misses the user’s explicit correction about **links and link events**.

A worker following this plan could complete the transport listener and still leave the task materially unfinished.

### 2. The public model is too narrow if it only centers transport events
Even if transport events are implemented, the plan should define the broader connectivity model deliberately:
- transport snapshot type
- link snapshot type
- transport event type wrapping a transport
- link event type wrapping a link

This is the stable architectural foundation that lets `SessionInfo.transports()` and `SessionInfo.links()` share the same value objects used by events. Without that, the implementation is likely to flatten fields now and then need a public API redesign immediately after.

### 3. Listener lifecycle must match zenoh-kotlin declaration conventions
The plan’s listener wrapper approach is not yet anchored to how this repo manages long-lived declarations.

In this codebase, long-lived Zenoh entities are usually modeled as `SessionDeclaration`s with:
- `undeclare()`
- `close()` delegating to `undeclare()`
- validity state
- session-managed cleanup through `Session.close()`

That matters here because connectivity listeners are long-lived JNI-backed declarations. The plan should explicitly choose a repo-consistent lifecycle model for **both** transport and link listeners rather than introducing a one-off wrapper shape.

### 4. One Kotlin implementation detail in the plan is incorrect
The plan says a new top-level `JNISessionInfo` object can access `session.jniSession` because it is in the same Kotlin module. That is not correct for `SessionInfo`’s current definition:
- `class SessionInfo(private val session: Session)`

A separate top-level object cannot access that private property. This is not the main architectural blocker, but it is a sign the plan is not yet tight enough to guide implementation safely.

## Non-blocking but important guidance
These are not the reason for rejection, but the revised plan should account for them:
- The new connectivity data/event types should fit the existing `Callback<T : ZenohType>` / `Handler<T : ZenohType, R>` abstractions if the API is meant to reuse the existing callback/handler/channel pattern.
- The new API surface should be marked `@Unstable`, matching the rest of the repo and the upstream status of the feature.
- If the planner wants to omit any upstream connectivity surface intentionally, that must be stated as an explicit scope decision with justification. Right now the omissions look accidental.

## Recommended revision
Revise the plan so it covers the connectivity family coherently:
1. Keep the API under `SessionInfo`.
2. Add public unstable snapshot types for **Transport** and **Link**.
3. Add public unstable **TransportEvent** and **LinkEvent** types that wrap those snapshots.
4. Add `SessionInfo.transports()` and `SessionInfo.links()`.
5. Add `declareTransportEventsListener(...)` and `declareLinkEventsListener(...)` with the same callback/handler/channel shape, if that is the chosen Kotlin binding pattern.
6. Make the listener wrappers follow the repo’s declaration lifecycle conventions, or explicitly justify any divergence.
7. Fix the Kotlin bridge design so it does not rely on illegal access to `SessionInfo`’s private state.

## Bottom line
This is not a matter of missing file paths or code snippets. The plan currently points implementation at only part of the required API surface and leaves enough ambiguity around lifecycle and public modeling that a worker could build the wrong thing. It should be revised before implementation starts.
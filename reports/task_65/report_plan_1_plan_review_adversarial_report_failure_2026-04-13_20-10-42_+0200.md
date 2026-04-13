I reviewed the plan against the current zenoh-kotlin codebase, the issue text, the Rust 1.8 SessionInfo API, and the referenced zenoh-go analog.

## Verdict
The plan has significant architectural issues and should be revised before implementation.

## What is sound
- Putting the API on `SessionInfo` is directionally correct. Rust exposes transport connectivity on `session.info()`, and the current Kotlin `Session.info()` already returns `SessionInfo`.
- Reusing the callback/handler/channel style from existing Kotlin APIs is a good fit.
- Using JNI callbacks and attaching daemon threads is consistent with existing Rust JNI code (`liveliness.rs`, `sample_callback.rs`, `utils.rs`).

## Blocking issues

### 1. The plan appears under-scoped for the requested "connectivity API"
The issue explicitly points to the zenoh-go implementation, and the Rust `SessionInfo` connectivity surface is broader than just a transport-events listener.

Relevant upstream surfaces:
- Rust `SessionInfo` has unstable `transports()` and `transport_events_listener()`.
- The zenoh-go analog referenced by the issue adds a `Transport` snapshot type plus `Transports()` and transport event listeners.
- The same family also includes links/link listeners upstream, though whether links are in scope can be decided separately.

The proposed plan only adds `declareTransportEventsListener()`. It does **not** add a `Transport` type or a `SessionInfo.transports()` query. That is a meaningful mismatch with both the Rust API and the go analog the issue tells us to follow.

A worker following this plan could finish the listener and still not have implemented the expected connectivity API surface.

### 2. The proposed public model is too flattened and diverges from upstream
The plan defines:
- `TransportEvent(kind, zid, whatAmI)`

That throws away the upstream shape, where a transport event contains a **transport snapshot**, and transport exposes more than just zid/whatami.

Rust `Transport` exposes at least:
- `zid()`
- `whatami()`
- `is_qos()`
- `is_multicast()`
- `is_shm()` when the feature is available

The zenoh-go analog also models this as:
- `Transport`
- `TransportEvent(kind, transport)`

Flattening the event to only `zid` and `whatAmI` is a poor API choice because it:
1. Drops transport properties already present upstream.
2. Makes `SessionInfo.transports()` awkward to add later, since there is no reusable `Transport` value type.
3. Moves away from the exact design the issue asks to emulate.

The plan should instead introduce a `Transport` snapshot type and make `TransportEvent` hold a `Transport`.

### 3. Listener lifecycle is not aligned with repository conventions
The proposed `TransportEventsListener<R>` only implements `AutoCloseable` and forwards `close()` to JNI.

That is inconsistent with the repo's listener/declaration pattern:
- `MatchingListener` implements `SessionDeclaration`, `AutoCloseable`, `isValid()`, `undeclare()`, and nulls its JNI handle.
- `SampleMissListener` follows the same pattern.
- Session-managed declarations are tracked through `SessionDeclaration` in `Session.close()`.

For a session-level declared listener, the plan should explicitly decide and document one of these designs:
1. Model it as a proper declaration (`SessionDeclaration` + `undeclare()` + validity state), consistent with other listeners.
2. If it intentionally is *not* a declaration, explain why that lifecycle difference is safe and desirable.

As written, the plan picks neither clearly. That is risky because session-close / listener-close interaction is central for these JNI-backed handles.

## Important non-blocking gaps
These are not the main reason for rejection, but they show the plan has not been grounded enough in the existing codebase:

- `TransportEvent` should implement `ZenohType`, otherwise it cannot be used with the existing `Callback<T : ZenohType>` / `Handler<T : ZenohType, R>` abstractions.
- The new public API should almost certainly be marked `@Unstable`, consistent with other unstable Kotlin surfaces and with the Rust API docs.
- If the listener is intended to match existing listener ergonomics, consider whether a background variant is expected, since other listener-style unstable APIs in this repo expose both retained-listener and background forms.

## Recommended revision
Revise the plan around this shape:

1. Keep the API under `SessionInfo`.
2. Introduce a public unstable `Transport` snapshot type that mirrors upstream/go semantics.
3. Make `TransportEvent` contain `kind + transport`, not flattened fields.
4. Add `SessionInfo.transports()` alongside transport event listening if the task is indeed the connectivity API analog from go.
5. Make the listener follow the repo's existing declaration/listener lifecycle pattern (`SessionDeclaration`/`undeclare`/validity), or explicitly justify a different lifecycle.
6. Ensure the Kotlin event type participates in the existing callback/handler abstractions (`ZenohType`).

## Evidence inspected
- Issue #647: asks to implement connectivity API and explicitly references the zenoh-go implementation approach.
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionInfo.kt`: current Kotlin surface is minimal and would need deliberate extension.
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/MatchingListener.kt` and `SampleMissListener.kt`: existing listener lifecycle pattern.
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/Callback.kt`, `Handler.kt`, `ZenohType.kt`: callback/handler type constraints.
- `zenoh-jni/src/liveliness.rs`, `sample_callback.rs`, `utils.rs`: JNI callback/lifecycle patterns.
- Rust docs for `SessionInfo`, `Transport`, and `TransportEvent`: confirm upstream connectivity surface and transport fields.
- zenoh-go `zenoh/transport.go` and `tests/connectivity_test.go`: confirm the analog includes `Transport`, `TransportEvent`, and `Transports()` in addition to listeners.

Because of the scope mismatch and the flattened public model, I do not consider this plan ready for implementation.
I reviewed the latest plan against the current Kotlin/JNI codebase, the Rust docs for `SessionInfo`, and the linked zenoh-go reference PR.

## Verdict

The plan is **generally sound** now. The earlier blockers appear resolved:
- The codebase precedent is indeed **callback + handler + channel + background** for event-style APIs (`AdvancedPublisher`, `AdvancedSubscriber`).
- Using **snapshot/value-style `Transport` and `Link` objects** is consistent with the zenoh-go PR summary; reconstructing a native `Transport` only for link filtering is a reasonable adaptation.
- The proposed separate JNI object is **not inherently inconsistent** with this repository: `JNILiveliness` already uses the same pattern of a singleton JNI facade that takes `jniSession.sessionPtr.get()`.
- The Rust docs confirm the expected unstable `SessionInfo` surface: `transports()`, `links()`, `transport_events_listener()`, `link_events_listener()`, with `history(true)` on both listener builders and `.transport(transport)` filtering on link listeners.

That said, the plan still leaves a few details underspecified enough that the implementer could make avoidable public-API mistakes.

## Remaining concerns

### 1. The exact Kotlin method matrix is still too implicit

The summary says `SessionInfo.kt` will expose **4 sync getters / 16 listener overloads**, but that count does not map cleanly onto either:
- the current Kotlin conventions, or
- the Rust builder surface.

Before implementation, the plan should list the **actual Kotlin signatures** that will exist.

At minimum, it should make explicit:
- whether link transport filtering is represented as
  - an **optional `transport: Transport? = null` parameter** on the normal link-listener overloads, or
  - **separate filtered overloads**;
- which methods return owned listener objects vs `Result<Unit>` background registrations;
- whether `history` is a defaulted Boolean on all listener declarations.

Without that signature list, the worker still has to guess the public API shape.

### 2. The event object shape should be stated explicitly

The zenoh-go PR notes a refinement that matters here: `TransportEvent` and `LinkEvent` should not duplicate all transport/link fields directly. Instead, they should expose:
- `kind`, and
- the associated `transport()` / `link()` payload.

The plan summary talks about snapshot types and JNI reconstruction, but it does **not** say whether the public event model follows the Rust/Go pattern or flattens fields onto the event itself. That should be decided up front, because it affects both Kotlin API design and JNI marshalling.

### 3. The unstable-API contract should be called out explicitly

The Rust connectivity API is unstable, and this repository consistently annotates corresponding Kotlin surfaces with `@Unstable` (`AdvancedPublisher`, `AdvancedSubscriber`, `MatchingListener`, `SampleMissListener`, related handlers/callbacks).

The plan should explicitly include `@Unstable` on:
- new public `Transport`, `Link`, `TransportEvent`, `LinkEvent` types,
- new listener classes, and
- the new `SessionInfo` connectivity methods.

That is probably what the implementer will do anyway, but it is important enough to be part of the plan rather than left implicit.

## What I checked

- `SessionInfo.kt` is currently a thin wrapper over `Session` and only exposes `zid()`, `peersZid()`, `routersZid()`.
- `AdvancedPublisher.kt` and `AdvancedSubscriber.kt` establish the current public overload pattern: callback / handler / channel, plus background variants.
- `Session.kt` lifecycle management relies on `strongDeclarations` for owned long-lived entities and `Session.close()` undeclares them before closing the native session.
- `JNILiveliness.kt` shows that a singleton JNI facade receiving `JNISession.sessionPtr.get()` is already accepted in this codebase.
- Rust docs for `SessionInfo`, `TransportEventsListenerBuilder`, and `LinkEventsListenerBuilder` confirm the expected unstable methods and the link transport filter.
- The zenoh-go PR summary confirms value-like `Transport`/`Link` objects and native reconstruction only when a transport filter must be passed back into native code.

## Recommendation

Proceed, but tighten the written plan first by adding:
1. the exact Kotlin public signatures,
2. the final `TransportEvent` / `LinkEvent` data shape, and
3. explicit `@Unstable` coverage.

I would not block implementation on architecture anymore, but I would want those API details pinned down before the worker starts writing files.
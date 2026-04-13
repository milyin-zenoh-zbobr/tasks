I reviewed the plan against the current zenoh-kotlin codebase and the upstream zenoh / zenoh-go connectivity APIs. The plan has the right general direction on one key point — using pure Kotlin snapshot types plus Rust-side reconstruction for transport filtering is consistent with the issue and with upstream `Transport::new_from_fields()` — but it is still incomplete in ways that would block a clean implementation.

## What is solid

- The issue explicitly points to zenoh-go PR 17, and that upstream work did introduce pure value/snapshot `Transport` and `Link` types with Rust/C-side reconstruction for filtering. That part of the plan is sound.
- The repo already follows the owned/background listener split for advanced features (`AdvancedPublisher` / `AdvancedSubscriber`), so reusing that high-level Kotlin UX is reasonable.
- The Rust dependency really does expose `Transport::new_from_fields()` behind `internal`, and `zenoh-jni/Cargo.toml` enables `features = ["unstable", "internal"]`, so reconstruction is feasible.

## Blocking issues

### 1. The plan’s file/layer breakdown is too narrow for the actual Kotlin surface area
The current summary only accounts for:
1. `SessionInfo.kt`
2. `JNIConnectivity.kt`
3. `zenoh-jni/src/connectivity.rs`

That is not enough for the API shape the plan itself proposes. Based on existing repo conventions, implementation will also need explicit Kotlin API/support types for at least:
- `Transport`
- `Link`
- `TransportEvent`
- `LinkEvent`
- owned listener handle classes (the equivalent of `MatchingListener` / `SampleMissListener`)
- JNI callback interfaces for the new event payloads

Right now there are no existing connectivity types anywhere in the repo, and there are no generic listener handles that can just be reused. If these files/types are not called out explicitly, the worker is missing critical implementation scope.

### 2. The handler/channel overload story is underspecified and currently not implementable with existing generic helpers
This is the biggest technical gap.

The repo’s generic callback/channel pipeline is constrained to `ZenohType`:
- `Callback<T : ZenohType>`
- `Handler<T : ZenohType, R>`
- `ChannelHandler<T : ZenohType>`

But connectivity events are not `ZenohType` today, and the current `ZenohType` docs explicitly describe it as the network-delivered trio: `Sample`, `Reply`, and `Query`.

The plan correctly noticed that `Callback<T : ZenohType>` is not directly reusable and proposed custom callback interfaces, but that is only half the problem. If the public API really exposes callback + handler + channel overloads, then the plan must also explicitly choose one of these approaches:
- introduce dedicated handler/channel abstractions for `TransportEvent` and `LinkEvent`, similar to the custom `Matching*` and `SampleMiss*` families, or
- broaden the core generic handler abstractions beyond `ZenohType`, which would be a much wider refactor.

Without making that decision explicit, the proposed overload matrix is not actually implementable as written.

### 3. The plan does not explicitly account for `@Unstable` on the new public API
All analogous advanced/listener features in this repo are annotated `@Unstable`, and upstream zenoh marks the connectivity APIs unstable as well. The plan should explicitly require `@Unstable` on the new public Kotlin surface (types and methods). As written, this stability aspect is missing.

## Important gaps that should be added before implementation

### 4. Listener lifecycle types and registration behavior need to be spelled out
For owned listeners, the plan mentions adding them to `Session.strongDeclarations`, which is directionally correct, but it should state clearly:
- what the owned listener classes are called,
- that they implement `SessionDeclaration` / `AutoCloseable`,
- how `undeclare()` maps to JNI free/close,
- and that session-scoped listeners must follow the same lifecycle expectations as other session-bound declarations.

The current summary assumes this behavior without naming the concrete Kotlin classes that provide it.

### 5. Tests are not explicit enough
The issue references zenoh-go’s connectivity work, and that PR added dedicated coverage for:
- empty transports/links lists,
- history-enabled listeners,
- link-event transport filtering,
- background listener paths.

The revised plan summary does not explicitly commit to equivalent Kotlin coverage. Given the amount of new JNI surface and lifecycle behavior, the implementation plan should require tests for at least:
- `transports()` non-empty and empty cases,
- `links()` non-empty and empty cases,
- `links(transport)` filtering,
- owned transport-events listener,
- background transport-events listener,
- owned link-events listener,
- background link-events listener,
- history flag behavior,
- transport filter behavior on link events,
- cleanup on listener close / session close.

Without that, the plan is too easy to implement incompletely.

## Non-blocking suggestion

Using a standalone `JNIConnectivity` object may work, but it is less consistent with the current structure than extending `JNISession`, which already owns session-native operations and the session pointer. I would not block on this if the plan is revised clearly, but the current codebase pattern favors keeping session-native JNI entry points under `JNISession` unless there is a strong reason not to.

## Recommended revision

Before implementation, revise the plan so it explicitly includes:
1. the full public Kotlin type set (`Transport`, `Link`, `TransportEvent`, `LinkEvent`, listener handle classes),
2. the callback/handler/channel strategy that resolves the `ZenohType` constraint,
3. `@Unstable` on the new public API,
4. the listener lifecycle wiring in `Session` / `SessionInfo`, and
5. a concrete connectivity test matrix covering history, filter, background, and empty-list cases.

Once those points are added, the plan should be ready.
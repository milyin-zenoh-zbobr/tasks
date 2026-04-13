The plan is ready. Here's a summary of what it covers:

## Plan Summary

**Goal**: Implement the full connectivity API (`transports()`, `links()`, transport/link event listeners) for zenoh-kotlin, addressing all previous adversarial review blockers.

### Key design decisions

1. **Transport and Link are pure Kotlin data classes** — `Transport::new_from_fields()` exists in zenoh 1.8.0 (confirmed in the actual cargo checkout) and is accessible via the `internal` feature already enabled in `zenoh-jni/Cargo.toml`. When filtering links by transport, Kotlin passes Transport fields as primitives and Rust reconstructs using this function. No native pointers needed in Kotlin.

2. **Full 6-overload API per listener type** — 3 owned (callback, handler, channel) + 3 background variants, matching the `AdvancedPublisher.declareMatchingListener` / `AdvancedSubscriber.declareSampleMissListener` patterns exactly.

3. **Custom callback/handler types** — `TransportEventsCallback`, `TransportEventsHandler<R>`, etc. follow the `SampleMiss` pattern rather than `Callback<T: ZenohType>`. No `ZenohType` needed.

4. **Transport filter on link events end-to-end** — `transport: Transport? = null` on all 6 link listener overloads; Rust passes through `Transport::new_from_fields()`.

5. **Session lifecycle** — New `internal fun addToStrongDeclarations()` helper on `Session.kt`; owned listeners are registered there via `SessionInfo`.

6. **Separate `JNIConnectivity` + `connectivity.rs`** — 8 JNI functions in a top-level file (not `ext/`), takes session ptr from `jniSession.sessionPtr.get()`.

7. **11 tests** in `ConnectivityTest.kt` covering all cases.
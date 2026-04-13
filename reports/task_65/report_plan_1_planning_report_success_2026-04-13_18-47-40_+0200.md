# Connectivity API Implementation Plan — Final Report

## Key Findings

- `Transport::new_from_fields()` exists in zenoh 1.8.0 and is `#[zenoh_macros::internal]` — accessible since zenoh-jni has `features = ["unstable", "internal"]`. This allows pure Kotlin snapshot types with clean Rust-side reconstruction for filters.
- The correct API pattern is AdvancedPublisher/AdvancedSubscriber: 3 owned + 3 background overloads (callback, handler, channel) — NOT callback-only.
- `SampleMiss` precedent: `TransportEvent`/`LinkEvent` need custom callback interfaces (not `Callback<T: ZenohType>`).
- Session.strongDeclarations is private; solution is `internal fun addToStrongDeclarations()` on Session.
- JNIConnectivity takes session ptr from `jniSession.sessionPtr.get()`.
- Background listeners use `.background()` Rust builder which returns `()`, no Arc needed.

## Architecture Summary

3 layers:
1. `SessionInfo.kt` — 4 sync getters/16 listener overloads total (8 per event type × 2 types)
2. `JNIConnectivity.kt` — internal object with 8 external JNI functions
3. `zenoh-jni/src/connectivity.rs` — 8 JNI C functions

All described in plan file at /data/home/skynet/.claude/plans/rustling-shimmying-castle.md
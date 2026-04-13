The plan is complete. Here's a summary of what it covers:

## Plan Summary

**Problem**: Previous plan (ctx_rec_7) was rejected because it was missing the full Kotlin type set, a workable handler/channel strategy for non-`ZenohType` events, `@Unstable` annotations, lifecycle details, and a concrete test matrix.

**Solution**: A fully specified 3-layer implementation:

### Layer 1 — Kotlin API (SessionInfo)
- 2 synchronous getters: `transports()` and `links(transport?)`
- 12 listener overloads (6 for transport events × [callback/handler/channel] × [owned/background], same for link events)
- All new public surface annotated `@Unstable`

### Layer 2 — JNI bridge (JNISession + new callback interfaces)
- 4 new JNI callback `fun interface` types (2 sync per-item, 2 async event)
- 6 new methods + 6 new `private external fun` on `JNISession`
- Dedicated `TransportEventCallback/Handler/ChannelHandler` and `Link*` equivalents — mirrors the exact `SampleMiss*`/`Matching*` pattern that already exists for non-ZenohType events

### Layer 3 — Rust (`session_info.rs`)
- 8 JNI C functions: 2 sync getters (iterate via callback), 4 listeners (2 transport × owned/background), 2 free-ptr functions for owned listener cleanup
- Uses `Transport::new_from_fields` (`#[internal]`) for optional transport filter reconstruction

### Tests
15 cases in `ConnectivityTest.kt` covering empty/non-empty transports and links, filter behavior, owned/background listeners for both event types, history flag, DELETE events, and lifecycle cleanup.
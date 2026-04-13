The plan is complete. Here's a summary of what it covers:

## Plan Summary

**Goal**: Implement the full connectivity API on `SessionInfo` — mirroring Rust 1.8's `session.info()` surface and the zenoh-go analog.

### What's implemented:

1. **4 new Kotlin data types**: `Transport`, `Link`, `TransportEvent`, `LinkEvent` — all `@Unstable`, matching upstream field shapes (not flattened)

2. **2 listener classes**: `TransportEventsListener` and `LinkEventsListener` — both implement `SessionDeclaration` + `AutoCloseable` + `isValid()` + `finalize()` (exact `MatchingListener`/`SampleMissListener` lifecycle pattern)

3. **Public API on `SessionInfo`**:
   - `transports(): Result<List<Transport>>` — snapshot
   - `links(transport?): Result<List<Link>>` — snapshot with optional transport filter
   - 6 overloads (callback/handler/channel × foreground/background) for each listener type

4. **JNI layer**: New `JNISessionInfo` internal object (follows `JNILiveliness` pattern), 4 new callback interfaces, 2 JNI pointer holders, and a new `connectivity.rs` Rust file with 8 exported JNI functions

5. **Key Rust design**: Uses the public builder API (`.transport_events_listener().callback(fn).wait()`) so dropping the Arc triggers zenoh's own `Drop` impl which properly undeclares from the session state

6. **Example**: `ZConnectivity.kt` demonstrating all four areas
The plan is ready. Here's a summary of the key design decisions that resolve all prior blocking issues:

**Core fixes from previous rejections:**

1. **`Transport` is a pure `data class`** — no hidden JNI pointers. Both transports from `transports()` snapshots and transports received in event payloads (`TransportEvent.transport`) are identical value objects and can both be used as filters interchangeably.

2. **Transport filter reconstruction** — When Kotlin passes a `Transport` filter to JNI (for `links(transport)` or link event listeners), the Rust side calls `Transport::new_from_fields(zid, whatami, is_qos, is_multicast)`. This works because:
   - The `internal` feature IS enabled on the zenoh dep (confirmed in `Cargo.toml`)
   - The `is_shm` parameter is conditionally compiled out when `shared-memory` is absent (confirmed in the upstream source)

3. **Session lifecycle** — Foreground `TransportEventsListener` and `LinkEventsListener` are added to `Session.strongDeclarations` (like Subscribers), so they keep running without an explicit reference and are cleaned up on session close.

4. **No `isShm`** — omitted entirely since `shared-memory` is not in zenoh-jni's feature set.

5. **Correct build command** — `cargo build` (no `--features` flag; `unstable` is already on the zenoh dependency).
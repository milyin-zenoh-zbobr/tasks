The plan is complete. Here's a summary of the key design decisions:

## Plan Summary

**Three blocking issues from prior reviews — all resolved:**

1. **Transport filter (was: zid-only, unsound)** → Now: Arc pointer round-trip. `getTransports` returns each Transport's `Arc::into_raw` pointer alongside data fields. Kotlin stores it in `JNINativeTransport(ptr: Long)`. When filtering links/link-event-listeners, that ptr is passed back to JNI which does `Arc::from_raw + clone + mem::forget`. This correctly identifies specific transport instances even when multiple exist for the same peer.

2. **`isShm` field (was: included unconditionally)** → Omitted entirely. The `shared-memory` feature is absent from `zenoh-jni/Cargo.toml`; only `unstable` + `internal` are enabled on the zenoh dependency.

3. **Verification command (was: `cargo build --features unstable`, fails)** → `cargo build` with no flags, since zenoh-jni defines no local `unstable` feature.

**Architecture follows existing patterns exactly:**
- Callback/Handler/Channel types modeled after `SampleMissCallback`/`SampleMissHandler`/`SampleMissChannelHandler`
- 6 overloads per listener type (callback/handler/channel × foreground/background)
- `history: Boolean` option on all listener variants; `transport: Transport?` filter on link listeners
- `Transport` is a regular class (not data class) to avoid ptr field issues with Kotlin's `copy()`
- `interfaces: Vec<String>` marshalled as Java `String[]` (not delimiter-joined)
- 23 files to create or extend
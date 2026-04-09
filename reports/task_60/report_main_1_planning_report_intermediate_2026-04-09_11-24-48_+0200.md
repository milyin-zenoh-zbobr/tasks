## Issue Identified

The current `zc_internal_transport_from_fields` implementation has an ABI mismatch:

- Rust uses `#[cfg(feature = "shared-memory")] is_shm: bool` as a function *parameter*
- cbindgen does **not** support `#[cfg]` on individual parameters — it generated `is_shm` unconditionally in the C header
- For non-SHM builds: Rust function has 5 params, C header declares 6 → ABI mismatch

## Proposed Fix

Split the single Rust function into two fully `#[cfg]`-gated variants:

1. `#[cfg(all(feature = "unstable", not(feature = "shared-memory")))]` — 5 params (no `is_shm`)
2. `#[cfg(all(feature = "unstable", feature = "shared-memory"))]` — 6 params (with `is_shm: bool`)

cbindgen handles `#[cfg]` on entire functions correctly (confirmed by `z_transport_is_shm` analog and `not(feature = "unstable")` usage in session.rs). This will generate two conditionally-gated C declarations in `include/zenoh_commons.h`:
- `#if (defined(Z_FEATURE_UNSTABLE_API) && !defined(Z_FEATURE_SHARED_MEMORY))` — 5-param signature
- `#if (defined(Z_FEATURE_UNSTABLE_API) && defined(Z_FEATURE_SHARED_MEMORY))` — 6-param signature

## Files to change
- `src/info.rs` — split one function into two `#[cfg]`-gated variants
- `include/zenoh_commons.h` — regenerate after the split
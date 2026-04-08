## Plan Summary

**Approach:** Add a single `Transport::new_from_fields()` constructor in `zenoh/src/api/info.rs`, gated with `#[zenoh_macros::internal]`, following the exact pattern of the existing `Transport::empty()` method.

**Key decisions:**
- Uses `#[zenoh_macros::internal]` feature gate (not `unstable`) to keep it accessible to language bindings but hidden from public docs
- `is_shm` parameter conditionally included via `#[cfg(feature = "shared-memory")]`
- Placed in the same impl block as `empty()` for consistency

**Analog:** `Transport::empty()` at line 246 of `zenoh/src/api/info.rs`

**Checklist:** 2 items — one for the implementation, one for verification builds/tests.
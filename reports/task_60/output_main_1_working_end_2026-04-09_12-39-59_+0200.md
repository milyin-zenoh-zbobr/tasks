All done. Here's a summary of what was implemented:

**Changes in `src/info.rs`:**
- Removed `zc_internal_transport_from_fields` (which incorrectly used `#[cfg]` on function parameters — unsupported by cbindgen)
- Added `zc_internal_create_transport_options_t` struct with `is_shm` as a cfg-gated field (cbindgen supports `#[cfg]` on struct fields, not function params)
- Added `zc_internal_create_transport_options_default()` constructor
- Added `zc_internal_create_transport()` function taking the options struct

**Regenerated `include/zenoh_commons.h`:**
- `is_shm` field is correctly wrapped in `#if defined(Z_FEATURE_SHARED_MEMORY)` in the struct definition
- ABI is consistent across feature combinations
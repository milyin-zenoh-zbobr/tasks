## Plan Summary

User approved the approach from ctx_rec_16.

### Design decisions
- Use an options struct (`zc_internal_create_transport_options_t`) instead of individual function parameters, following the `z_publisher_options_t` analog in `src/publisher.rs`
- `#[cfg(feature = "shared-memory")]` on a struct field IS supported by cbindgen — it emits `#ifdef Z_FEATURE_SHARED_MEMORY` around that field in the C header, solving the ABI mismatch from the previous approach
- The old `zc_internal_transport_from_fields` (with `#[cfg]` on a parameter — unsupported by cbindgen) is removed entirely
- Function renamed to `zc_internal_create_transport` per user requirement

### Files to change
- `src/info.rs` — add struct + default fn, replace old function
- `include/zenoh_commons.h` — regenerate via `cargo build`
## What to do

After modifying `src/info.rs` (new struct + renamed function), regenerate the C header:

```
cargo build
```

Or run cbindgen directly if available. Verify the generated `include/zenoh_commons.h` contains:
- `zc_internal_create_transport_options_t` struct definition with `is_shm` wrapped in `#ifdef Z_FEATURE_SHARED_MEMORY`
- `zc_internal_create_transport` function declaration
- No `zc_internal_transport_from_fields` declaration (old name removed)
- No unconditional `is_shm` parameter in any function signature

## Why
The header must be kept in sync with the Rust source. cbindgen correctly handles `#[cfg]` on struct fields (wraps in `#ifdef`), so the regenerated header will have the correct conditional ABI.
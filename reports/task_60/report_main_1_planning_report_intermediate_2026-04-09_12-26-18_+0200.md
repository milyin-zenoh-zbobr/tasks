## Plan

### Problem
`#[cfg]` on individual function parameters is not supported by cbindgen — `is_shm` was emitted unconditionally in the C header causing ABI mismatch (Rust 5-param vs C 6-param in non-SHM builds).

### Solution
1. **New struct `zc_internal_create_transport_options_t`** in `src/info.rs` (gated `#[cfg(feature = "unstable")]`):
   - `#[repr(C)]` with fields: `zid`, `whatami`, `is_qos`, `is_multicast`
   - Conditional: `#[cfg(feature = "shared-memory")] pub is_shm: bool`
   - `Default` impl + `zc_internal_create_transport_options_default()` constructor

2. **Replace `zc_internal_transport_from_fields` → `zc_internal_create_transport`**:
   - New signature: `(this_: &mut MaybeUninit<z_owned_transport_t>, options: &zc_internal_create_transport_options_t)`
   - Extract fields from struct, handle `is_shm` with `#[cfg(feature = "shared-memory")]`

3. **Regenerate `include/zenoh_commons.h`** — cbindgen will correctly wrap `is_shm` in `#ifdef Z_FEATURE_SHARED_MEMORY` in the C struct definition.

### Analog
`z_publisher_options_t` in `src/publisher.rs` — same pattern of `#[repr(C)]` struct with cfg-gated fields.

### Verification
- `cargo build` with and without `--features shared-memory`
- Header contains struct with `is_shm` inside `#ifdef`, new function name, no old function name
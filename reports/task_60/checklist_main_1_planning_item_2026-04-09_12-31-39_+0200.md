## What to do

In `src/info.rs`, replace the current `zc_internal_transport_from_fields` function (which has `#[cfg]` on an individual parameter — unsupported by cbindgen) with:

1. **New struct `zc_internal_create_transport_options_t`** (gate with `#[cfg(feature = "unstable")]`):
   - `#[repr(C)]` struct with fields: `zid: z_id_t`, `whatami: z_whatami_t`, `is_qos: bool`, `is_multicast: bool`
   - Conditional field: `#[cfg(feature = "shared-memory")] pub is_shm: bool` — this `#[cfg]` on a struct field IS supported by cbindgen and will emit `#ifdef Z_FEATURE_SHARED_MEMORY` around that field in the C header
   - `impl Default` for the struct (follow the pattern from `z_publisher_options_t` in `src/publisher.rs`)
   - `zc_internal_create_transport_options_default()` constructor function (follow `z_publisher_options_default` pattern)

2. **Rename `zc_internal_transport_from_fields` → `zc_internal_create_transport`**:
   - New signature: `(this_: &mut MaybeUninit<z_owned_transport_t>, options: &zc_internal_create_transport_options_t)`
   - Extract all fields from the options struct; handle `is_shm` with `#[cfg(feature = "shared-memory")]` when passing to `Transport::new_from_fields`
   - Remove the old function entirely

## Why
`#[cfg]` on individual function parameters is not supported by cbindgen — the old approach caused ABI mismatch (is_shm emitted unconditionally in the C header). Using a struct makes the conditional field work correctly: cbindgen wraps the struct field in `#ifdef`, keeping ABI consistent across feature combinations.

## Analog
`z_publisher_options_t` / `z_publisher_options_default` / `z_declare_publisher` in `src/publisher.rs` — same `#[repr(C)]` struct with cfg-gated fields pattern.
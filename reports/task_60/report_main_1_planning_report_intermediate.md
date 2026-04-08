# Transport from_fields Implementation Plan

## Approach

Add a new `src/transport.rs` module (gated under `#[cfg(feature = "unstable")]`) that wraps the Rust `Transport` type from zenoh, following the exact same pattern as the `Hello` type in `src/scouting.rs`.

## Files to Change

### 1. `Cargo.toml`
Comment out all zenoh dep lines pointing to `eclipse-zenoh/zenoh:main` and add replacements pointing to `milyin/zenoh:zbobr_fix-59-implement-transport-from-fields-constructor`. Affects all 4 zenoh deps in both `[dependencies]` and `[build-dependencies]`.

### 2. `build-resources/opaque-types/src/lib.rs`
Add `Transport` import and two opaque type entries (gated under `#[cfg(feature = "unstable")]`):
- `get_opaque_type_data!(Option<Transport>, z_owned_transport_t)`
- `get_opaque_type_data!(Transport, z_loaned_transport_t)`

### 3. `src/transport.rs` (new file)
Full Transport C API gated under `#[cfg(feature = "unstable")]`:
- Standard lifecycle: drop, loan, loan_mut, check, null, clone
- `z_transport_from_fields()` using `Transport::new_from_fields()`
- Accessors: `z_transport_zid()`, `z_transport_whatami()`, `z_transport_is_qos()`, `z_transport_is_multicast()`, `z_transport_is_shm()` (last one conditional on shared-memory)

### 4. `src/lib.rs`
Add transport module registration under `#[cfg(feature = "unstable")]`.

## Why unstable?
Transport accessor methods in zenoh are gated under `feature = "unstable"`. Since zenoh-c propagates `unstable` to zenoh via `[features] unstable = ["zenoh/unstable", ...]`, gating the whole transport module under unstable ensures all required zenoh APIs are available.

## Analogue: Hello type in scouting.rs
The implementation mirrors exactly the Hello pattern — same macro, same lifecycle functions, same accessor style.
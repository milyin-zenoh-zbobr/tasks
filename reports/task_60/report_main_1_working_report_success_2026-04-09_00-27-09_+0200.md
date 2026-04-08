# Task completed: zc_internal_transport_from_fields

## Changes made

### Cargo.toml / Cargo.toml.in / build-resources/opaque-types/Cargo.toml
- Commented out existing `eclipse-zenoh/zenoh.git` branch `main` dependency lines
- Added replacement lines pointing to `milyin-zenoh-zbobr/zenoh.git` branch `zbobr_fix-59-implement-transport-from-fields-constructor`
- Covers: zenoh, zenoh-ext, zenoh-runtime, zenoh-util in [dependencies] and zenoh in [build-dependencies]
- Original lines kept as comments for easy restore when upstream PR merges

### src/info.rs
Added two new functions after `z_internal_transport_null`:

1. **`zc_internal_transport_from_fields`** (`#[cfg(feature = "unstable")]`)
   - Parameters: `this_: &mut MaybeUninit<z_owned_transport_t>, zid: z_id_t, whatami: z_whatami_t, is_qos: bool, is_multicast: bool`
   - Calls `Transport::new_from_fields(zid, whatami, is_qos, is_multicast, #[cfg(feature = "shared-memory")] false)`
   - Writes `Some(transport)` to `this_`

2. **`zc_internal_transport_from_fields_shm`** (`#[cfg(all(feature = "unstable", feature = "shared-memory"))]`)
   - Same as above but also accepts `is_shm: bool` and passes it to `new_from_fields`

## Verification
- `cargo build --features unstable` — passes
- `cargo build --features unstable,shared-memory` — passes
- CMake build with `ZENOHC_BUILD_WITH_SHARED_MEMORY=ON ZENOHC_BUILD_WITH_UNSTABLE_API=ON` — passes
- Both symbols appear in generated `include/zenoh_commons.h`

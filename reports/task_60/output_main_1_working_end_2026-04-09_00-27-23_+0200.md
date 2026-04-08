All done. Here's a summary of what was implemented:

## Summary

**Cargo.toml / Cargo.toml.in / build-resources/opaque-types/Cargo.toml**: Commented out the `eclipse-zenoh/zenoh.git` main branch deps and added replacements pointing to `milyin-zenoh-zbobr/zenoh.git` branch `zbobr_fix-59-implement-transport-from-fields-constructor`. Original lines kept as comments for easy restore.

**src/info.rs**: Added two new functions after `z_internal_transport_null`:

1. `zc_internal_transport_from_fields` — gated by `#[cfg(feature = "unstable")]`, takes `(this_, zid, whatami, is_qos, is_multicast)`, calls `Transport::new_from_fields` (using `is_shm=false` when shared-memory feature is active).

2. `zc_internal_transport_from_fields_shm` — gated by `#[cfg(all(feature = "unstable", feature = "shared-memory"))]`, also takes `is_shm: bool`.

Both symbols appear in the generated `include/zenoh_commons.h`. CMake build with `ZENOHC_BUILD_WITH_SHARED_MEMORY=ON` and `ZENOHC_BUILD_WITH_UNSTABLE_API=ON` passes successfully.
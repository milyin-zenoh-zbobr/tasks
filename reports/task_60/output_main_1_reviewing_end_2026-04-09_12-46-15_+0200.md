Review complete. The implementation passes all checks:

- `zc_internal_create_transport_options_t` struct correctly introduced with `#[cfg(feature = "shared-memory")]`-gated `is_shm` field
- Function renamed from `zc_internal_transport_from_fields` to `zc_internal_create_transport` 
- Header regenerated with proper `#if defined(Z_FEATURE_SHARED_MEMORY)` guard around `is_shm`
- Exhaustive `match` on `z_whatami_t` provides compile-time safety
- `Cargo.toml.in`, `Cargo.toml`, and `build-resources/opaque-types/Cargo.toml` all consistently point to the fork with commented-out originals for easy restoration
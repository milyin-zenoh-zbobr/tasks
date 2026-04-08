## Fix: expose is_shm parameter in zc_internal_transport_from_fields

### Change
Added `#[cfg(feature = "shared-memory")] is_shm: bool` to the function signature in `src/info.rs`, replacing the hardcoded `false` that was previously passed to `Transport::new_from_fields`.

### Files changed
- `src/info.rs`: added `#[cfg(feature = "shared-memory")] is_shm: bool` parameter and updated the call to `Transport::new_from_fields` to pass `is_shm` instead of `false`; added `@param is_shm` doc comment
- `include/zenoh_commons.h`: regenerated — the C signature now includes `bool is_shm` within the `#if defined(Z_FEATURE_UNSTABLE_API)` guard

### Build verification
Built with `ZENOHC_BUILD_WITH_SHARED_MEMORY=ON` and `ZENOHC_BUILD_WITH_UNSTABLE_API=ON` — passes with no warnings.

### Commit
`21f51c4f` fix: expose is_shm parameter in zc_internal_transport_from_fields
# Test Planning Report: zc_internal_create_transport

## Summary

The implementation added three new public C API symbols (all gated on `Z_FEATURE_UNSTABLE_API`):
- `zc_internal_create_transport_options_t` struct (`is_shm` additionally gated on `Z_FEATURE_SHARED_MEMORY`)
- `zc_internal_create_transport_options_default()` 
- `zc_internal_create_transport()`

No existing tests exercise these symbols. Three tests are required, all to be added to `tests/z_api_info.c` inside the `#if defined(Z_FEATURE_UNSTABLE_API)` block and called from `main()`.

## Tests Required

### 1. `test_zc_internal_create_transport_options_default` (ctx_rec_23)
Verifies all default field values of the options struct are correct per documentation: `whatami=CLIENT`, `is_qos=false`, `is_multicast=false`, and (`is_shm=false` under `Z_FEATURE_SHARED_MEMORY`).

### 2. `test_zc_internal_create_transport_all_whatami` (ctx_rec_24)
Iterates over all three `z_whatami_t` variants (CLIENT, PEER, ROUTER), creates a transport for each with a distinct ZID and `is_qos=true`, then asserts the ZID, whatami, and bool flags round-trip correctly through the Rust→C boundary using the accessor functions (`z_transport_zid`, `z_transport_whatami`, `z_transport_is_qos`, `z_transport_is_multicast`).

### 3. `test_zc_internal_create_transport_drop` (ctx_rec_25)
Verifies ownership semantics: transport is valid after creation, gravestone after `z_drop(z_move(...))`. Ensures no double-free or sanitizer errors.

## Tests Not Needed
- Shared-memory path (`is_shm=true`): requires SHM feature enabled; the field presence is already tested by the compile-time guard in the header; runtime SHM behavior is not part of this API's contract.
- Invalid `whatami` values: not reachable from C without UB; the Rust `match` is exhaustive at compile time.

## Verification
```
cmake -B build -DZENOHC_BUILD_WITH_UNSTABLE_API=ON && cmake --build build && ctest --test-dir build -R z_api_info -V
```

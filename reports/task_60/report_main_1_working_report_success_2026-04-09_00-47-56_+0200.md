# Fix: explicit whatami and remove _shm constructor

## Issues addressed (from ctx_rec_8 review)

### 1. Wildcard whatami fallback fixed
Changed the `whatami` match in `zc_internal_transport_from_fields` from:
```rust
_ => WhatAmI::Client,  // silently coerced invalid values
```
to explicit enumeration of all three variants:
```rust
z_whatami_t::ROUTER => WhatAmI::Router,
z_whatami_t::PEER => WhatAmI::Peer,
z_whatami_t::CLIENT => WhatAmI::Client,
```
The Rust `#[repr(C)]` enum only has these three valid discriminants, so the match is now exhaustive with no wildcard. This matches the pattern used in `z_transport_whatami()` and `z_hello_whatami()`.

### 2. Unapproved `zc_internal_transport_from_fields_shm` removed
Removed the entire function and its docs from `src/info.rs`. The approved scope was a single `zc_internal_transport_from_fields` constructor. The shared-memory path is handled internally via `#[cfg(feature = "shared-memory")]` conditional compilation passing `false` for the `is_shm` argument.

## Verification
- `cargo build --features unstable` — passes, no warnings
- `cargo build --features unstable,shared-memory` — passes, no warnings
- CMake build with `ZENOHC_BUILD_WITH_SHARED_MEMORY=ON ZENOHC_BUILD_WITH_UNSTABLE_API=ON` — passes
- Generated `include/zenoh_commons.h` contains only `zc_internal_transport_from_fields` (no `_shm` variant)

## Files changed
- `src/info.rs`: fixed match, removed _shm function
- `include/zenoh_commons.h`: regenerated (removed _shm declaration, ~20 lines removed)

# Review Report

## Summary

The two checklist items from the previous review cycle (ctx_rec_9, ctx_rec_10) are correctly implemented. However, the user's explicit instruction that accompanied those items was only partially fulfilled: the `is_shm` conditional parameter was NOT added to `zc_internal_transport_from_fields`, contrary to the user's stated requirement.

---

## Correctly Implemented

### 1. Cargo dependency retargeting (Cargo.toml / Cargo.toml.in / build-resources/opaque-types/Cargo.toml)
- All four zenoh deps (`zenoh`, `zenoh-ext`, `zenoh-runtime`, `zenoh-util`) in `[dependencies]` and `zenoh` in `[build-dependencies]` are correctly commented-out (not deleted) and replaced by the fork lines.
- `Cargo.toml` and `Cargo.toml.in` are identical in content for these sections. ✓
- `build-resources/opaque-types/Cargo.toml` updated consistently to the same fork/branch. ✓
- Both `Cargo.lock` files reflect the new fork commit `fc811c22cb72df973af27a3b002e0d3c40011ab7`. ✓
- No unrelated lockfile changes observed. ✓

### 2. Wildcard whatami fixed (ctx_rec_9) ✓
The match in `zc_internal_transport_from_fields` is now exhaustive:
```rust
let whatami = match whatami {
    z_whatami_t::ROUTER => WhatAmI::Router,
    z_whatami_t::PEER => WhatAmI::Peer,
    z_whatami_t::CLIENT => WhatAmI::Client,
};
```
This mirrors `z_transport_whatami()` exactly. ✓

### 3. `zc_internal_transport_from_fields_shm` removed (ctx_rec_10) ✓
The separate `_shm` variant is absent from `src/info.rs` and `include/zenoh_commons.h`. ✓

### 4. Header cleanliness ✓
`include/zenoh_commons.h` adds only `zc_internal_transport_from_fields`, gated by `#if defined(Z_FEATURE_UNSTABLE_API)`. No unrelated autogeneration noise. ✓

### 5. Analog pattern consistency ✓
- Placement: immediately after `z_internal_transport_null` ✓
- `#[cfg(feature = "unstable")]` gating ✓
- `MaybeUninit` write pattern (follows `z_transport_clone`) ✓
- `pub extern "C" fn` without `unsafe` (consistent with `z_transport_clone` and `z_transport_drop`) ✓

---

## Issue: `is_shm` Conditional Parameter Not Exposed

The user's instruction after the previous review was:
> "There is a condition for shared memory support. When shm is enabled, add additional parameter to function, like it's done in rust."

This requires the single `zc_internal_transport_from_fields` function to accept `is_shm: bool` as a conditional parameter (present only when `feature = "shared-memory"` is enabled), parallel to how the Rust `Transport::new_from_fields` exposes it.

**What was implemented instead:**
```rust
let transport = Transport::new_from_fields(
    zid, whatami, is_qos, is_multicast,
    #[cfg(feature = "shared-memory")] false,  // ← hardcoded false
);
```

The C header exposes only:
```c
void zc_internal_transport_from_fields(z_owned_transport_t*, z_id_t, z_whatami_t, bool, bool);
```

This means when the library is built with `shared-memory` support, callers can never construct a transport with `is_shm = true`. The parameter is silently forced to `false` with no way for the caller to override it.

**Required implementation:**
```rust
pub extern "C" fn zc_internal_transport_from_fields(
    this_: &mut MaybeUninit<z_owned_transport_t>,
    zid: z_id_t,
    whatami: z_whatami_t,
    is_qos: bool,
    is_multicast: bool,
    #[cfg(feature = "shared-memory")] is_shm: bool,
) {
    ...
    let transport = Transport::new_from_fields(
        zid, whatami, is_qos, is_multicast,
        #[cfg(feature = "shared-memory")] is_shm,
    );
    ...
}
```

The generated C header should then conditionally include `is_shm` via an `#ifdef` guard (as cbindgen handles `#[cfg]`-gated parameters). This follows the SHM gating pattern already established in `z_transport_is_shm` (`#[cfg(all(feature = "unstable", feature = "shared-memory"))]`).

The worker removed the `_shm` variant as required (ctx_rec_10), but did not complete the second half of the user's requirement — folding the SHM parameter into the main function signature. The checklist item (ctx_rec_10) only captured "remove the extra function" and missed "add is_shm conditional parameter", making the checklist incomplete. The omission was not caught.

---

## Required Fix

In `src/info.rs`, add `#[cfg(feature = "shared-memory")] is_shm: bool` as a function parameter to `zc_internal_transport_from_fields` and pass it through to `Transport::new_from_fields` instead of hardcoding `false`. Regenerate `include/zenoh_commons.h` so the C signature conditionally includes `is_shm`.

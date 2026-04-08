## Plan Summary

**Goal:** Expose a `zc_transport_from_fields` constructor in zenoh-c that builds a `z_owned_transport_t` from individual fields, using a new `Transport::from_fields(...)` API added in the zenoh fork.

### Change 1 — `Cargo.toml`
Redirect all four zenoh dependencies (`zenoh`, `zenoh-ext`, `zenoh-runtime`, `zenoh-util`) from `eclipse-zenoh/zenoh.git @ main` to `milyin-zenoh-zbobr/zenoh.git @ zbobr_fix-59-implement-transport-from-fields-constructor`. Comment out the original lines (don't delete) for easy restore when the upstream PR merges.

### Change 2 — `src/info.rs`
Add `zc_transport_from_fields` near the other transport constructors (after `z_internal_transport_null`, ~line 228):
- Gated by `#[cfg(feature = "unstable")]`
- Parameters: `this_: &mut MaybeUninit<z_owned_transport_t>`, `zid: z_id_t`, `whatami: z_whatami_t`, `is_qos: bool`, `is_multicast: bool` (+ `is_shm: bool` under `shared-memory` feature, following the fork's API)
- Converts `z_whatami_t` → `WhatAmI` (same match as `z_transport_whatami()`)
- Calls `Transport::from_fields(...)` from the fork
- Writes `Some(transport)` into `this_`
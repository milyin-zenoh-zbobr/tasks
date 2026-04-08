In `src/info.rs`, add a new function `zc_internal_transport_from_fields` immediately after `z_internal_transport_null` (~line 230).

Function contract:
- Gate with `#[cfg(feature = "unstable")]` (and an additional `#[cfg(all(feature = "unstable", feature = "shared-memory"))]` variant or extra parameter for `is_shm` if the fork's API requires it — check the fork's `Transport::from_fields` signature first)
- Signature: `(this_: &mut MaybeUninit<z_owned_transport_t>, zid: z_id_t, whatami: z_whatami_t, is_qos: bool, is_multicast: bool)`
- Convert `z_whatami_t` → `WhatAmI` using the same match pattern as `z_transport_whatami()` in the same file
- Convert `z_id_t` → `ZenohId` using the existing transmute/into_rust_type helpers from `src/transmute.rs`
- Call `Transport::from_fields(...)` from the forked zenoh crate
- Write result: `this_.as_rust_type_mut_uninit().write(Some(transport))`

Analogs to follow:
- `z_internal_transport_null` — MaybeUninit write pattern
- `z_transport_clone` — writing `Some(transport)` into `this_`
- `z_transport_whatami` — z_whatami_t → WhatAmI conversion
- `z_transport_is_shm` — feature = "shared-memory" gating pattern
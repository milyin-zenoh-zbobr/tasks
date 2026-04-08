# Plan: Transport `from_fields` constructor in zenoh-c

## Context

Issue #1263 requires a `zc_` internal function in zenoh-c that constructs a `z_owned_transport_t` from individual field arguments (zid, whatami, is_qos, is_multicast). The `z_owned_transport_t` type already exists in `src/info.rs`, wrapping zenoh's `Transport` struct. The fork `milyin-zenoh-zbobr/zenoh` branch `zbobr_fix-59-implement-transport-from-fields-constructor` adds a `from_fields` constructor to `Transport` in zenoh-rust; zenoh-c needs to update its dependency and expose this via a `zc_` function.

## Change 1: `Cargo.toml`

Redirect the four zenoh dependencies (`zenoh`, `zenoh-ext`, `zenoh-runtime`, `zenoh-util`) from `eclipse-zenoh/zenoh.git` on `main` to `milyin-zenoh-zbobr/zenoh.git` on `zbobr_fix-59-implement-transport-from-fields-constructor`. Comment out the original lines (not delete) for easy restore when the upstream PR merges. Apply to both `[dependencies]` and `[build-dependencies]` sections if zenoh appears in both.

## Change 2: `src/info.rs`

Add `zc_transport_from_fields` near the other transport constructors (~line 228, after `z_internal_transport_null`):

- Gated by `#[cfg(feature = "unstable")]`
- Signature: `(this_: &mut MaybeUninit<z_owned_transport_t>, zid: z_id_t, whatami: z_whatami_t, is_qos: bool, is_multicast: bool)`
- Under `shared-memory` feature, also accept `is_shm: bool` (follow the fork's API)
- Convert `z_whatami_t` → `WhatAmI` using same match as `z_transport_whatami()`
- Convert `z_id_t` → `ZenohId` via the transmute helpers
- Call `Transport::from_fields(...)` (internal API from the fork)
- Write `Some(transport)` to `this_` via `as_rust_type_mut_uninit().write(...)`

## Analogs

- `z_internal_transport_null()` — MaybeUninit write pattern
- `z_transport_whatami()` — z_whatami_t → WhatAmI conversion
- `Transport::empty()` in zenoh — precedent for internal constructors

## Verification

1. `cargo build --features unstable` compiles against the fork
2. `zc_transport_from_fields` symbol appears in generated C header
3. Optionally test that field accessors return expected values on a constructed transport

# Task: Implement Transport from-fields constructor

## What was done

Added `Transport::new_from_fields()` to `zenoh/src/api/info.rs` in the same `impl Transport` block as `empty()`, following the exact same pattern:

- Gated with `#[zenoh_macros::internal]`
- Parameters: `zid: ZenohId`, `whatami: WhatAmI`, `is_qos: bool`, `is_multicast: bool`, plus `is_shm: bool` under `#[cfg(feature = "shared-memory")]`
- Directly initializes the `Transport` struct fields

## Verification

- `cargo build -p zenoh --features internal` — ✅ success
- `cargo build -p zenoh --features internal,shared-memory` — ✅ success
- `cargo test -p zenoh` — ✅ all 21+ tests pass (run via `/tmp` target dir due to `/data` disk being full)

## Commit

`0366230d3` — feat: add Transport::new_from_fields() internal constructor

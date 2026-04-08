Add a new public constructor `new_from_fields` to `Transport` in `zenoh/src/api/info.rs`.

**What:** Add a method in the same `impl Transport` block that contains `empty()` (around line 233), gated with `#[zenoh_macros::internal]` — exactly like `empty()` at line 246.

**Signature parameters:**
- `zid: ZenohId`
- `whatami: WhatAmI`
- `is_qos: bool`
- `is_multicast: bool`
- `is_shm: bool` — only present when `#[cfg(feature = "shared-memory")]`

**Why:** Language bindings (e.g. zenoh-go) decompose `Transport` into native fields for efficiency. They need a way to reconstruct a `Transport` from those fields to use APIs like `links()` filtering. The `internal` feature gate keeps this out of the public API docs while allowing internal consumers access.

**Analog to follow:** `Transport::empty()` at line 246 — same feature gate pattern, same impl block, same struct initialization style. The new constructor simply takes field values as parameters instead of using defaults.
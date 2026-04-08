## Plan: Implement Transport from-fields constructor

### Context
GitHub issue #2554: Language bindings (e.g. zenoh-go) decompose `Transport` into native fields for efficiency. There's no way to reconstruct a Rust `Transport` from those fields, preventing use of the decomposed type for `links()` filtering.

### Approach
Add an internal (feature-gated) constructor to `Transport` in `zenoh/src/api/info.rs` that accepts all fields as parameters.

**Analog:** `Transport::empty()` at line 246 of info.rs — same feature gate, same impl block.

**Constructor signature:**
- `zid: ZenohId`
- `whatami: WhatAmI`
- `is_qos: bool`
- `is_multicast: bool`
- `is_shm: bool` (only under `#[cfg(feature = "shared-memory")]`)

**Feature gate:** `#[zenoh_macros::internal]` — keeps it hidden from public API docs, accessible only to internal consumers like language bindings.

### Verification
- `cargo build` with `internal` feature
- `cargo build` with `internal` + `shared-memory` features
- Existing tests pass
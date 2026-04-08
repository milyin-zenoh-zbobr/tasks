**Test plan summary:**

Two unit tests are needed in `zenoh/src/api/info.rs` (new `#[cfg(test)] mod tests` block at the bottom), both gated on `#[cfg(all(test, feature = "internal"))]`:

1. **`test_new_from_fields_stores_fields`** — Constructs a `Transport` via `new_from_fields()` with known non-default values and asserts each `pub(crate)` field equals the input argument (including `is_shm` under `shared-memory` feature).

2. **`test_new_from_fields_equals_new_from_peer`** — Builds a `TransportPeer`, constructs a `Transport` via both `Transport::new()` and `Transport::new_from_fields()` with identical data, and asserts `==`. This validates the new constructor against the authoritative production path, catching any field mis-assignment.

Verification: `cargo test -p zenoh --features internal -- info::tests` and with `shared-memory` added.
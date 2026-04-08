# Test Planning Report: Transport::new_from_fields()

## Summary

The implementation adds a single constructor `Transport::new_from_fields()` in `zenoh/src/api/info.rs`. There are currently no unit tests in that file. Two tests are needed to provide meaningful behavioral coverage.

## Tests Required

### 1. Field assignment correctness (`test_new_from_fields_stores_fields`)
- Gate: `#[cfg(all(test, feature = "internal"))]`
- Constructs a `Transport` via `new_from_fields()` with known, non-default values
- Asserts each `pub(crate)` field equals the corresponding argument
- Includes a `#[cfg(feature = "shared-memory")]` block to cover `is_shm`
- Located in a new `#[cfg(test)] mod tests` block at the bottom of `info.rs`

### 2. Equivalence with `Transport::new()` (`test_new_from_fields_equals_new_from_peer`)
- Gate: `#[cfg(all(test, feature = "internal"))]`
- Constructs a `TransportPeer` and builds a `Transport` both via `Transport::new()` and via `new_from_fields()` with the same values
- Asserts `==` (Transport derives PartialEq)
- Validates the constructor against the production path, catching any field mis-assignment

## What Was Ruled Out

- Tests that assert on prompt text or config literal values (not applicable here)
- Snapshot/serialization tests (no serde impl on Transport directly)
- Tests for the `#[zenoh_macros::internal]` gate itself (compile-time enforcement, not runtime)

## Files to Modify

- `zenoh/src/api/info.rs` — add `#[cfg(test)] mod tests { ... }` at the bottom

## Verification Commands

```
cargo test -p zenoh --features internal -- info::tests
cargo test -p zenoh --features internal,shared-memory -- info::tests
```

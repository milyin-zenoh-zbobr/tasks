# Plan approved and checklist items created

## Approach
User approved the plan with one name change: `zc_internal_transport_from_fields` (was `zc_transport_from_fields`).

## Checklist items
1. **Point Cargo.toml to fork** — Comment out eclipse-zenoh/zenoh.git deps and add milyin-zenoh-zbobr/zenoh.git on zbobr_fix-59-implement-transport-from-fields-constructor
2. **Add `zc_internal_transport_from_fields`** in `src/info.rs` after `z_internal_transport_null`, gated by `#[cfg(feature = "unstable")]`, following MaybeUninit write pattern and existing conversion helpers

## Key design decisions
- Function is `zc_internal_` (not `z_`) prefix to match the naming convention for internal-only APIs
- Gated behind `unstable` feature, consistent with all other transport-related functions
- Cargo.toml originals are commented (not deleted) for easy restore when upstream PR merges

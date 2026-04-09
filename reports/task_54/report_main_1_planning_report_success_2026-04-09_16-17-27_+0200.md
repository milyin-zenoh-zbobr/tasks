## Plan: Implement Connectivity API 2

The user approved the plan (comment: "Proceed with plan"). Checklist items have been created covering all implementation steps.

### Approach chosen
Copy the upstream `connectivity_api` branch as base, then apply two key changes:
1. Make `Transport` and `Link` pure Go value structs (no C ownership, no `Drop()`/`Clone()`) — same pattern as `TransportEvent`/`LinkEvent`
2. Use `option.Option[Transport]` instead of `*Transport` in options structs

### Key design decisions
- **Move semantics for filtering**: `zc_internal_create_transport` creates a temporary C-owned transport from Go fields; it is moved into the C options struct (ownership transferred to C). No manual drop.
- **Analog**: `TransportEvent` and `LinkEvent` are the direct templates for the redesigned `Transport` and `Link` structs.
- **Submodule**: Switch to `milyin-zenoh-zbobr/zenoh-c` branch `zbobr_fix-60-transport-from-fields` with original URL documented for easy rollback.

### Checklist items created (ctx_rec_3 through ctx_rec_9)
1. Update zenoh-c submodule
2. Copy base files from upstream connectivity_api branch
3. Redesign Transport as pure Go struct
4. Redesign Link as pure Go struct
5. Change options from *Transport to option.Option[Transport]
6. Implement filtering with zc_internal_create_transport (move semantics)
7. Update examples and tests
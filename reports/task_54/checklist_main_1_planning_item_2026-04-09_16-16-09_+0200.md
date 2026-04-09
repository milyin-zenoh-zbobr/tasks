Redesign the `Link` struct in `zenoh/link.go` to be a pure Go value type, following the exact same pattern as `LinkEvent`.

**What to change**:
- Replace `link *C.z_owned_link_t` with flat fields matching `LinkEvent` (all the same fields except `kind`): `zId`, `src`, `dst`, `group`, `mtu`, `isStreamed`, `interfaces`, `authIdentifier`, `priorityMin`, `priorityMax`, `hasPriorities`, `reliability`, `hasReliability`
- Remove `Drop()` and `Clone()` methods entirely
- Reuse `extractLinkSnapshot` or create an `extractLink` helper (same logic, returns `Link` instead of `LinkEvent`) to populate the struct from a loaned C link
- Update `zenohLinkCallback` to call this helper and pass the Go value to the channel/closure

**Why**: Same reasoning as Transport — users should not manage Link memory. Extract at callback time; no C resources escape into Go userland.

**Analog**: `LinkEvent` in `zenoh/link.go` — identical fields minus `kind`. The extraction helper should be near-identical.
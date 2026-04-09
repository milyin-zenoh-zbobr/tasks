# Review Report: TransportEvent/LinkEvent Accessor Refactor

## Summary
All 3 checklist items for this phase are correctly implemented. The implementation follows the Rust API pattern where event types wrap their data struct via an accessor rather than repeating the full surface API.

## Checklist Verification

### ctx_rec_21: Refactor TransportEvent to wrap Transport struct
✅ **Correctly implemented.** `TransportEvent` in `zenoh/transport.go` now has:
- Single `transport Transport` field (replacing 5 duplicated fields)
- `Transport() Transport` pointer-receiver accessor method
- `zenohTransportEventsCallback` simplified to `TransportEvent{kind: kind, transport: extractTransportSnapshot(loanedTransport)}`
- The 5 duplicated methods (`ZId`, `WhatAmI`, `IsQos`, `IsMulticast`, `IsShm`) are removed

### ctx_rec_22: Refactor LinkEvent to wrap Link struct
✅ **Correctly implemented.** `LinkEvent` in `zenoh/link.go` now has:
- Single `link Link` field (replacing 10 duplicated fields)
- `Link() Link` pointer-receiver accessor method
- `extractLinkSnapshot` simplified to `LinkEvent{kind: kind, link: extractLink(loanedLink)}`
- All 10 duplicated methods removed

### ctx_rec_23: Update tests and examples
✅ **Correctly implemented.** All call sites updated:
- `tests/connectivity_test.go`: All `evt.ZId()` → `evt.Transport().ZId()` etc. for TransportEvent; all `evt.ZId()` → `evt.Link().ZId()` etc. for LinkEvent
- `examples/z_info/z_info.go`: Transport and link event callbacks use the new accessors

## Code Quality

**Positive aspects:**
1. Clean separation — `Transport` and `Link` are pure Go snapshots with no C resources; events wrap them logically
2. The Rust API pattern (`evt.Transport()`, `evt.Link()`) is faithfully followed
3. CGO safety fix in `buildCTransport` (C-heap allocation to avoid "Go pointer to unpinned Go pointer" panic) is correct and well-commented

**Minor observation:**
- `buildCTransport` uses `*(*uint32)(unsafe.Pointer(&cOpts.whatami)) = uint32(t.whatAmI)` instead of a direct cast `C.z_whatami_t(t.whatAmI)`. This is functionally correct since both are 32-bit types, but the unsafe indirection is unnecessary if CGo allows the direct cast. Not a blocker — CGo sometimes requires this workaround for C enum types.
- `buildCTransport` lives in `link.go` rather than `transport.go`. Logically it belongs with Transport, but since it's only called from link-related options, placement in `link.go` is acceptable.

## Conclusion
Implementation is correct and complete. All 3 checklist items are done. The refactor cleanly follows the Rust API pattern and eliminates field/method duplication in event types.
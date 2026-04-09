# Refactor: TransportEvent/LinkEvent wrap Transport/Link via accessors

## Changes

### zenoh/transport.go
- `TransportEvent` now has a single `transport Transport` field instead of 5 duplicated fields (`zId`, `whatAmI`, `isQos`, `isMulticast`, `isShm`)
- Removed 5 duplicated methods (`ZId`, `WhatAmI`, `IsQos`, `IsMulticast`, `IsShm`) from `TransportEvent`
- Added `Transport() Transport` accessor method
- `zenohTransportEventsCallback` simplified: `TransportEvent{kind: kind, transport: extractTransportSnapshot(loanedTransport)}`

### zenoh/link.go
- `LinkEvent` now has a single `link Link` field instead of 10 duplicated fields
- Removed 10 duplicated methods from `LinkEvent`
- Added `Link() Link` accessor method
- `extractLinkSnapshot` simplified: `LinkEvent{kind: kind, link: extractLink(loanedLink)}`
- **Fixed pre-existing CGO bug**: `buildCTransport` now returns `*C.z_owned_transport_t` (C-heap allocated) instead of by value. This prevents the CGO "Go pointer to unpinned Go pointer" panic that occurred because `z_transport_move(&owned)` was storing a Go stack address inside a Go-stack `cOpts` variable. Now `&owned` is a C heap pointer, which is allowed inside Go memory passed to C. All 3 call sites updated to `defer C.free(unsafe.Pointer(ownedPtr))`.

### tests/connectivity_test.go
Updated all event field accesses:
- `evt.ZId()` → `evt.Transport().ZId()` (TransportEvent tests)
- `evt.WhatAmI()` → `evt.Transport().WhatAmI()`, etc.
- `evt.ZId()` → `evt.Link().ZId()` (LinkEvent tests)
- `evt.Src()`, `evt.Dst()`, `evt.Mtu()`, etc. → `evt.Link().Src()`, etc.

### examples/z_info/z_info.go
- `evt.ZId()` → `evt.Transport().ZId()` in transport event callback
- `evt.ZId()`, `evt.Src()`, `evt.Dst()` → `evt.Link().ZId()`, etc. in link event callback

## Test results
All tests pass: `go test ./tests/... -v` — 85 seconds, all PASS.
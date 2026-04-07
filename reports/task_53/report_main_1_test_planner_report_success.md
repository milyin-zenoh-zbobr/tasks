# Connectivity API — Test Plan

## Implementation reviewed
Branch `zbobr_fix-53-implement-connectivity-api` adds:
- `zenoh/transport.go` — Transport type, TransportEvent snapshot, TransportEventsListener, background variant, Session.Transports()
- `zenoh/link.go` — Link type, LinkEvent snapshot, LinkEventsListener, background variant, Session.Links()
- `tests/connectivity_test.go` — 9 existing tests

## Existing coverage
The 9 existing tests cover:
- Transports/Links listing with count and ZId assertions
- Transport-filtered link listing
- Foreground transport and link event listeners (PUT/DELETE, with history, with transport filter)
- Background transport events listener

## Gaps identified

### Untested accessor methods
- `Transport.WhatAmI()`, `IsQos()`, `IsMulticast()`, `IsShm()`, `Clone()`
- `TransportEvent.WhatAmI()`, `IsQos()`, `IsMulticast()`, `IsShm()`
- `Link.Src()`, `Dst()`, `Group()`, `Mtu()`, `IsStreamed()`, `Interfaces()`, `AuthIdentifier()`, `Priorities()`, `Reliability()`, `Clone()`
- `LinkEvent.Src()`, `Dst()`, `Group()`, `Mtu()`, `IsStreamed()`, `Interfaces()`, `AuthIdentifier()`, `Priorities()`, `Reliability()`

### Untested code paths
- `TransportEventsListener.Undeclare()` and `LinkEventsListener.Undeclare()`
- `DeclareBackgroundLinkEventsListener()` (background transport tested but background link is not)

### Snapshot consistency
- No test verifies that `LinkEvent` snapshot fields match the same link queried via synchronous `Links()`

## Tests to add (6 checklist items)

| # | Test name | What it validates |
|---|-----------|-------------------|
| 1 | TestTransportAccessors | WhatAmI=Peer, IsMulticast=false, IsShm=false, Clone preserves ZId |
| 2 | TestTransportEventAccessors | TransportEvent snapshot: WhatAmI, IsQos, IsMulticast, IsShm |
| 3 | TestLinkAccessors | Src/Dst non-empty, Mtu>0, IsStreamed=true for TCP, Group/AuthId empty, Clone consistency |
| 4 | TestLinkEventSnapshotFields | LinkEvent fields match synchronous Links() for same connection |
| 5 | TestListenerUndeclare | Undeclare() returns nil for both Transport and Link listeners; no events after undeclare |
| 6 | TestBackgroundLinkEventsListener | PUT and DELETE events delivered via background link listener |

All proposed tests validate observable behavior and C-binding correctness, not static config values.

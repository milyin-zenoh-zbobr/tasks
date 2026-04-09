Redesign the `Transport` struct in `zenoh/transport.go` to be a pure Go value type, following the exact same pattern as `TransportEvent`.

**What to change**:
- Replace `transport *C.z_owned_transport_t` with flat fields: `zId Id`, `whatAmI WhatAmI`, `isQos bool`, `isMulticast bool`, `isShm bool`
- Remove the `Drop()` and `Clone()` methods entirely
- Add an `extractTransportSnapshot(loaned *C.z_loaned_transport_t) Transport` helper function that reads fields from the loaned C transport and returns a populated Go struct. Mirror the `extractLinkSnapshot` pattern used for `LinkEvent`.
- Update `zenohTransportCallback` (the CGO export function) to call `extractTransportSnapshot` and pass the resulting Go value to the channel/closure — instead of cloning the C transport.

**Why**: Users should not need to call Drop() on Transport values. The C resources are only needed transiently during the callback; extracting to a Go snapshot at that point is safe and matches the TransportEvent/LinkEvent pattern.

**Analog**: `TransportEvent` in `zenoh/transport.go` — same fields, same extraction pattern. The only difference is TransportEvent has a `kind` field; Transport does not.
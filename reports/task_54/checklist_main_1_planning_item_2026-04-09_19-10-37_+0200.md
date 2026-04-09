In `zenoh/transport.go`, redesign `TransportEvent`:
- Replace the 5 duplicated fields (`zId`, `whatAmI`, `isQos`, `isMulticast`, `isShm`) with a single embedded `transport Transport` field.
- Remove the 5 duplicated methods: `ZId()`, `WhatAmI()`, `IsQos()`, `IsMulticast()`, `IsShm()`.
- Add a `Transport() Transport` accessor method that returns `e.transport`.
- Update `zenohTransportEventsCallback` to construct: `TransportEvent{kind: kind, transport: extractTransportSnapshot(loanedTransport)}` instead of manually copying each field.

This follows the Rust pattern where the event wraps the data struct rather than repeating its surface API.
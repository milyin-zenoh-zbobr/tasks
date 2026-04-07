# Connectivity API Implementation Plan for zenoh-go

## Context
zenoh-c PR #1171 introduced a Connectivity API exposing transport/link info and event listeners. This plan implements the corresponding Go bindings. Per user feedback, **both Transport and Link use equal approaches** — both wrap C owned structures with accessor methods, Clone, and Drop.

## Closest Analog
- **Subscriber** (`subscriber.go`) — owned C handle, Undeclare/Drop/Handler pattern for event listeners
- **Session.PeersZId()** (`session.go:123-148`) — synchronous closure-based collection for Transports()/Links()
- **ZId callback** (`session.go:17-35`) — lightweight C→Go callback bridge without CGO data extraction structs

## Design: Both Transport and Link Wrap C Structures

Both types follow the same pattern: Go struct holds `*C.z_owned_*_t`, provides accessor methods via `C.z_*_loan()`, and supports Clone/Drop.

### New Go Types

**Transport** (`transport.go`):
- Wraps `*C.z_owned_transport_t`
- Accessor methods: `ZId() Id`, `WhatAmI() WhatAmI`, `IsQos() bool`, `IsMulticast() bool`, `IsShm() bool`
- `Clone() Transport`, `Drop()`

**Link** (`link.go`):
- Wraps `*C.z_owned_link_t`
- Accessor methods: `ZId() Id`, `Src() string`, `Dst() string`, `Group() string`, `Mtu() uint16`, `IsStreamed() bool`, `Interfaces() []string`, `AuthIdentifier() string`, `Priorities() (min, max uint8, ok bool)`, `Reliability() (Reliability, bool)`
- `Clone() Link`, `Drop()`

**TransportEvent / LinkEvent** — lightweight Go structs with:
- `Kind() SampleKind` (PUT=connected/added, DELETE=disconnected/removed)
- `Transport() Transport` / `Link() Link` (cloned from event)

**TransportEventsListener / LinkEventsListener** — same pattern as Subscriber:
- `Handler() <-chan T`, `Undeclare() error`, `Drop()`

### New Session Methods

**Synchronous queries** (follows PeersZId pattern):
- `Session.Transports() ([]Transport, error)`
- `Session.Links(options *LinksOptions) ([]Link, error)`

**Event listeners** (follows DeclareSubscriber pattern):
- `Session.DeclareTransportEventsListener(handler, options) (TransportEventsListener, error)`
- `Session.DeclareBackgroundTransportEventsListener(closure, options) error`
- `Session.DeclareLinkEventsListener(handler, options) (LinkEventsListener, error)`
- `Session.DeclareBackgroundLinkEventsListener(closure, options) error`

### Options Structs
- `LinksOptions` — optional Transport filter (ownership transfer)
- `TransportEventsListenerOptions` — History bool
- `LinkEventsListenerOptions` — History bool, optional Transport filter (ownership transfer)

### C Bridge Pattern
- Transport/Link callbacks clone from loaned to owned (no CGO data extraction structs needed)
- Event callbacks extract kind + clone transport/link from event
- Bridge functions in zenoh_cgo.h/.c

### File Structure
1. `zenoh/transport.go` — Transport type + Session.Transports()
2. `zenoh/link.go` — Link type + Session.Links() + LinksOptions
3. `zenoh/connectivity.go` — Events, listeners, options, Session declare methods
4. `zenoh/zenoh_cgo.h` + `zenoh/zenoh_cgo.c` — C bridge additions
5. `examples/z_connectivity/z_connectivity.go` — Example

### Key Decisions
1. Both Transport and Link wrap C owned types equally (user requirement)
2. Clone in callbacks: closures clone loaned→owned so Go holds independent copies
3. Event kind reuses SampleKind (PUT=connect/add, DELETE=disconnect/remove)
4. Transport ownership transfer in filter options (matches C API move semantics)
## Connectivity API Implementation Plan for zenoh-go

### Context
zenoh-c PR #1171 introduced a Connectivity API that exposes information about active transports and links within a Zenoh session, plus event listeners for monitoring connect/disconnect events. This plan implements the corresponding Go bindings.

### Closest Analog
- **Liveliness module** (`liveliness.go`) for DeclareSubscriber/DeclareBackgroundSubscriber pattern
- **Session.PeersZId()/RoutersZId()** (`session.go`) for synchronous closure-based collection
- **Hello/Scout** (`scout.go`) for eagerly extracting C data into pure Go structs

### Proposed Go API

**New Types:**
- `Transport` — wraps `z_owned_transport_t`, provides accessor methods (ZId, WhatAmI, IsQos, IsMulticast, IsShm), Clone/Drop for ownership
- `Link` — pure Go struct with eagerly-copied fields (ZId, Src, Dst, Group, Mtu, IsStreamed, Interfaces, AuthIdentifier, Priorities, Reliability)
- `LinkPriorities` — {Min, Max uint8}
- `TransportEvent` — {Kind SampleKind, Transport}  (PUT=connected, DELETE=disconnected)
- `LinkEvent` — {Kind SampleKind, Link}  (PUT=added, DELETE=removed)
- `TransportEventsListener` / `LinkEventsListener` — listener handles with Handler()/Undeclare()/Drop()

**New Session Methods:**
- `Session.Transports() ([]Transport, error)` — synchronous list of all transports
- `Session.Links(options *LinksOptions) ([]Link, error)` — synchronous list of links, optionally filtered by transport
- `Session.DeclareTransportEventsListener(handler, options) (TransportEventsListener, error)`
- `Session.DeclareBackgroundTransportEventsListener(closure, options) error`
- `Session.DeclareLinkEventsListener(handler, options) (LinkEventsListener, error)`
- `Session.DeclareBackgroundLinkEventsListener(closure, options) error`

**Options:**
- `LinksOptions` — optional Transport filter
- `TransportEventsListenerOptions` — History bool
- `LinkEventsListenerOptions` — History bool, optional Transport filter

### Design Decisions
1. **Transport keeps C handle**: Unlike Link (which eagerly copies all fields), Transport wraps `z_owned_transport_t` because it needs to be passed back to C for filtering in Links/LinkEvents options (move semantics matching C API)
2. **Link is a pure Go struct**: All fields extracted eagerly from C, following the Hello pattern in scout.go
3. **Event kind reuses SampleKind**: PUT=connect/add, DELETE=disconnect/remove, matching the C API
4. **Synchronous collection for Transports()/Links()**: Following PeersZId()/RoutersZId() pattern

### Implementation Steps
1. Add C callback bridge functions in zenoh_cgo.h/c
2. Create `transport.go` with Transport type and C bridge
3. Create `link.go` with Link type and C bridge  
4. Create `connectivity.go` with events, listeners, options, and Session methods
5. Add `z_connectivity` example
6. Update `z_info` example with transport/link info

### Key Question
Should Transport be a pure Go value type (like Link/Hello) or keep the C handle for filter support? Keeping the C handle adds complexity (Clone/Drop) but is needed for the filtering use case in Links() and LinkEventsListener options. The alternative would be to use a different identifier for filtering.
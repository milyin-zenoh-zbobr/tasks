# Connectivity API Plan — Updated with Matching Listener Analogy

## Key Changes from Previous Plan
- Event listeners now explicitly follow the `MatchingListener` pattern from `zenoh/matching.go` (Handler/Drop/Undeclare + Background variant)
- C bridge extracts data by cloning in C callbacks (following subscriber pattern in `zenoh_cgo.c`), not passing loaned pointers to Go
- Tests modeled on `tests/matching_test.go` structure

## Architecture Summary

### C Bridge (zenoh_cgo.h/c)
4 bridge data structs + 4 C callback functions that clone transport/link from loaned pointers before calling Go. This follows the subscriber pattern where `zenohSubscriberCallback` extracts sample data.

### Go Types

**Transport** (`zenoh/transport.go`): wraps `*C.z_owned_transport_t`, accessors (ZId, WhatAmI, IsQos, IsMulticast, IsShm), Clone/Drop

**TransportEvent**: kind (SampleKind: PUT=connect, DELETE=disconnect) + owned Transport

**TransportEventsListener**: `listener *C.z_owned_transport_events_listener_t` + `receiver <-chan TransportEvent`, with Handler()/Drop()/Undeclare() — identical to MatchingListener pattern

**Link** (`zenoh/link.go`): wraps `*C.z_owned_link_t`, accessors (ZId, Src, Dst, Group, Mtu, IsStreamed, Interfaces, AuthIdentifier, Priorities, Reliability), Clone/Drop

**LinkEvent**: kind (SampleKind: PUT=added, DELETE=removed) + owned Link

**LinkEventsListener**: same pattern as TransportEventsListener

### Session Methods

Synchronous (PeersZId pattern):
- `Transports() ([]Transport, error)`
- `Links(options *InfoLinksOptions) ([]Link, error)` — optional transport filter

Event listeners (MatchingListener pattern):
- `DeclareTransportEventsListener(handler, options) (TransportEventsListener, error)`
- `DeclareBackgroundTransportEventsListener(closure, options) error`
- `DeclareLinkEventsListener(handler, options) (LinkEventsListener, error)`
- `DeclareBackgroundLinkEventsListener(closure, options) error`

### Options
- `TransportEventsListenerOptions`: History bool
- `LinkEventsListenerOptions`: History bool, Transport filter (optional)
- `InfoLinksOptions`: Transport filter (optional)

Transport filter is cloned internally — caller retains ownership.

### Files
- `zenoh/zenoh_cgo.h` + `zenoh/zenoh_cgo.c` — C bridge additions
- `zenoh/transport.go` — new
- `zenoh/link.go` — new
- `tests/connectivity_test.go` — new (9 tests)
- `examples/z_info/z_info.go` — extended

### Test Suite (9 tests following matching_test.go structure)
1. TestTransportsList
2. TestLinksList
3. TestLinksFilteredByTransport
4. TestTransportEventsListener
5. TestTransportEventsListenerWithHistory
6. TestBackgroundTransportEventsListener
7. TestLinkEventsListener
8. TestLinkEventsListenerWithHistory
9. TestLinkEventsListenerWithTransportFilter
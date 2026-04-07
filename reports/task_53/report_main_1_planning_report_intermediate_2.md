# Connectivity API Implementation Plan for zenoh-go

## Context
zenoh-c PR #1171 added a Connectivity API exposing transport/link information and event listeners. This plan implements the corresponding Go bindings, a test suite (modeled on `z_api_info.c`), and extends the `z_info` example (following `z_info.c`).

## Closest Analog
- **Transport/Link types**: Follow `Hello` in `scout.go` but with owned C handles (Clone/Drop) — both wrap C structures equally per user requirement
- **Synchronous collection**: Follow `PeersZId()`/`RoutersZId()` in `session.go:123-148`
- **Event listeners**: Follow `DeclareSubscriber`/`DeclareBackgroundSubscriber` in `subscriber.go`
- **Tests**: Follow `advanced_pub_sub_test.go` for isolated session pair creation
- **Example**: Follow `z_info.c` structure

## New Files
1. `zenoh/transport.go` — Transport type + `Session.Transports()`
2. `zenoh/link.go` — Link type + `Session.Links()` + LinksOptions
3. `zenoh/connectivity.go` — Events, listeners, options, Session.Declare* methods
4. `tests/connectivity_test.go` — Test suite (9 tests)

## Modified Files
5. `zenoh/zenoh_cgo.h` — C callback declarations
6. `zenoh/zenoh_cgo.c` — C callback implementations
7. `examples/z_info/z_info.go` — Extended with transport/link/event display

## API Surface

**Transport**: wraps `*C.z_owned_transport_t`, accessors (ZId, WhatAmI, IsQos, IsMulticast, IsShm), Clone/Drop

**Link**: wraps `*C.z_owned_link_t`, accessors (ZId, Src, Dst, Group, Mtu, IsStreamed, Interfaces, AuthIdentifier, Priorities, Reliability), Clone/Drop

**Session methods**:
- `Transports() ([]Transport, error)`, `Links(options *LinksOptions) ([]Link, error)`
- `DeclareTransportEventsListener`, `DeclareBackgroundTransportEventsListener`
- `DeclareLinkEventsListener`, `DeclareBackgroundLinkEventsListener`

**Events**: TransportEvent (Kind + Transport), LinkEvent (Kind + Link) — both wrap owned C handles

**Options**: LinksOptions (transport filter), TransportEventsListenerOptions (history), LinkEventsListenerOptions (history + transport filter)

## Test Suite (modeled on z_api_info.c)
1. TestTransportsAndLinks — session pair, verify 1 transport and 1 link with correct ZId
2. TestLinksFiltered — verify Links() filtering by transport
3. TestTransportEvents — connect/disconnect, verify PUT/DELETE events
4. TestTransportEventsHistory — history=true shows existing transports
5. TestTransportEventsBackground — background listener variant
6. TestLinkEvents — connect/disconnect link events
7. TestLinkEventsHistory — history=true for links
8. TestLinkEventsBackground — background link listener
9. TestLinkEventsFiltered — link events with transport filter

Uses isolated session pairs (router+peer on explicit TCP port, multicast disabled).

## z_info Example Extension
After existing peers section: print transports with properties, print links with properties, declare event listeners, wait for CTRL-C printing events.

## Implementation Order
1. C bridge → 2. Transport → 3. Link → 4. Events/Listeners → 5. Tests → 6. Example
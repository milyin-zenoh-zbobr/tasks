# Connectivity API Implementation — Complete

## Summary
All 5 checklist items are done across 2 commits on branch `zbobr_fix-53-implement-connectivity-api`.

## Commit 1 (pre-existing): `4db10e6`
- `zenoh/zenoh_cgo.h` — extern declarations for `zenohTransportEventsCallback`, `zenohTransportEventsDrop`, `zenohLinkEventsCallback`, `zenohLinkEventsDrop`, `zenohTransportCallback`, `zenohTransportDrop`, `zenohLinkCallback`, `zenohLinkDrop`
- `zenoh/transport.go` — `Transport` struct (wraps `*C.z_owned_transport_t`), accessors (ZId, WhatAmI, IsQos, IsMulticast, IsShm, Clone, Drop), `TransportEvent`, `TransportEventsListener`, `TransportEventsListenerOptions`, Session methods: `Transports()`, `DeclareTransportEventsListener`, `DeclareBackgroundTransportEventsListener`

## Commit 2: `485f868`
- `zenoh/link.go` — `Link` struct (wraps `*C.z_owned_link_t`), accessors (ZId, Src, Dst, Group, Mtu, IsStreamed, Interfaces, AuthIdentifier, Priorities, Reliability, Clone, Drop), `LinkEvent`, `LinkEventsListener`, `LinkEventsListenerOptions`, `InfoLinksOptions`, Session methods: `Links()`, `DeclareLinkEventsListener`, `DeclareBackgroundLinkEventsListener`
- `tests/connectivity_test.go` — 9 tests: TestTransportsList, TestLinksList, TestLinksFilteredByTransport, TestTransportEventsListener, TestTransportEventsListenerWithHistory, TestBackgroundTransportEventsListener, TestLinkEventsListener, TestLinkEventsListenerWithHistory, TestLinkEventsListenerWithTransportFilter. Uses peer-to-peer TCP connections with unique ports per test.
- `examples/z_info/z_info.go` — Extended to print transports and links, declare background transport/link event listeners, and wait for SIGINT/SIGTERM signal.

## Patterns followed
- `MatchingListener` pattern for event listener types (Handler/Drop/Undeclare + Background variant)
- `PeersZId()` pattern for synchronous `Transports()` and `Links()` iteration
- `matching_test.go` structure for test organization
- `config.go:Get()` pattern for C string extraction in Link accessors

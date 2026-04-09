# Plan: Make TransportEvent reuse Transport, LinkEvent reuse Link

## Problem
`TransportEvent` and `LinkEvent` currently duplicate all fields and methods of `Transport` and `Link` (plus a `kind` field). This is inconsistent with the Rust API where `LinkEvent.link()` returns a `Link` without repeating its surface.

## Approach
- `TransportEvent` gets a single `transport Transport` field + `Transport() Transport` accessor method. All 5 duplicated methods (`ZId`, `WhatAmI`, `IsQos`, `IsMulticast`, `IsShm`) are removed.
- `LinkEvent` gets a single `link Link` field + `Link() Link` accessor method. All 10 duplicated methods are removed.
- Internal constructors (`zenohTransportEventsCallback`, `extractLinkSnapshot`) are updated to build events using the new structure.
- Test and example callers are updated: `evt.ZId()` becomes `evt.Transport().ZId()` / `evt.Link().ZId()` etc.

## Files changed
- `zenoh/transport.go` — TransportEvent struct, callback
- `zenoh/link.go` — LinkEvent struct, extractLinkSnapshot, callback
- `tests/connectivity_test.go` — all event accessor call sites
- `examples/z_info/z_info.go` — example event callbacks

## What
Create `zenoh/transport.go` with the `Transport` type wrapping `*C.z_owned_transport_t`, the `TransportEvent` type, and the `TransportEventsListener` type following the MatchingListener pattern.

## Why
Transport represents a network-level connection to a remote peer. The Go type must wrap the C owned struct and expose accessor methods that map to C API functions.

## Transport struct
- Wraps `*C.z_owned_transport_t`
- Accessor methods: `ZId() Id`, `WhatAmI() WhatAmI`, `IsQos() bool`, `IsMulticast() bool`, `IsShm() bool`
- `Drop()` — calls `z_transport_drop(z_transport_move(...))`
- `Clone() Transport` — calls `z_transport_clone`

C API accessors used:
- `z_transport_zid(z_transport_loan(...))` → `z_id_t`
- `z_transport_whatami(z_transport_loan(...))` → `z_whatami_t`
- `z_transport_is_qos(z_transport_loan(...))` → `bool`
- `z_transport_is_multicast(z_transport_loan(...))` → `bool`
- `z_transport_is_shm(z_transport_loan(...))` → `bool`

## TransportEvent struct
- `Kind SampleKind` — `Z_SAMPLE_KIND_PUT` means transport connected, `Z_SAMPLE_KIND_DELETE` means disconnected
- `transport Transport` — the owned transport from the event
- Accessor: `Transport() *Transport`

The Go callback (`zenohTransportEventsCallback`) should:
1. Extract the event kind via `z_transport_event_kind(event)`
2. Clone the transport from the event via `z_transport_event_transport(event)` and `z_transport_clone`
3. Construct a `TransportEvent` and call the closure

## TransportEventsListener struct
Follow MatchingListener pattern exactly:
- Fields: `listener *C.z_owned_transport_events_listener_t`, `receiver <-chan TransportEvent`
- `Handler() <-chan TransportEvent`
- `Drop()` — calls `z_transport_events_listener_drop(z_transport_events_listener_move(...))`
- `Undeclare() error` — calls `z_undeclare_transport_events_listener(z_transport_events_listener_move(...))`

## TransportEventsListenerOptions
- `History bool` — when true, receive events for already-existing transports

## Session methods (can be in transport.go or session.go)

Synchronous:
- `Transports() ([]Transport, error)` — follows `PeersZId()` pattern: create a closure that appends to a slice, call `z_info_transports(z_session_loan(...), z_closure_transport_move(...))`. The callback clones each loaned transport into an owned one.

Event listeners:
- `DeclareTransportEventsListener(handler Handler[TransportEvent], options *TransportEventsListenerOptions) (TransportEventsListener, error)` — follows `DeclareMatchingListener` pattern
- `DeclareBackgroundTransportEventsListener(closure Closure[TransportEvent], options *TransportEventsListenerOptions) error` — follows `DeclareBackgroundMatchingListener` pattern

## Analog
- `zenoh/matching.go` — MatchingListener struct, DeclareMatchingListener/DeclareBackgroundMatchingListener methods
- `zenoh/session.go:PeersZId()` — for the synchronous Transports() method pattern
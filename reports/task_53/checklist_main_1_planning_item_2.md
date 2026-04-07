## What
Create `zenoh/link.go` with the `Link` type wrapping `*C.z_owned_link_t`, the `LinkEvent` type, and the `LinkEventsListener` type following the same pattern as Transport.

## Why
Link represents a physical network link within a transport. The Go type must wrap the C owned struct and expose all accessor methods from the C API.

## Link struct
- Wraps `*C.z_owned_link_t`
- Accessor methods:
  - `ZId() Id` — `z_link_zid(z_link_loan(...))`
  - `Src() string` — `z_link_src(z_link_loan(...), &owned_string)` then extract Go string and drop
  - `Dst() string` — same pattern with `z_link_dst`
  - `Group() string` — `z_link_group(z_link_loan(...), &owned_string)`
  - `Mtu() uint16` — `z_link_mtu(z_link_loan(...))`
  - `IsStreamed() bool` — `z_link_is_streamed(z_link_loan(...))`
  - `Interfaces() []string` — `z_link_interfaces(z_link_loan(...), &owned_string_array)`, iterate with `z_string_array_len`/`z_string_array_get`
  - `AuthIdentifier() string` — `z_link_auth_identifier(z_link_loan(...), &owned_string)`
  - `Priorities() (min uint8, max uint8, ok bool)` — `z_link_priorities(z_link_loan(...), &min, &max)`
  - `Reliability() (Reliability, bool)` — `z_link_reliability(z_link_loan(...), &reliability)`
- `Drop()` — `z_link_drop(z_link_move(...))`
- `Clone() Link` — `z_link_clone`

For string accessors: use `z_owned_string_t`, extract with `z_string_data`/`z_string_len`, convert to Go string, then drop. Follow the pattern in `config.go:Get()` which does similar string extraction.

## LinkEvent struct
- `Kind SampleKind` — PUT = link added, DELETE = link removed
- `link Link` — owned link from the event
- Accessor: `Link() *Link`

The Go callback (`zenohLinkEventsCallback`) should clone the link from the event using `z_link_event_link(event)` + `z_link_clone`.

## LinkEventsListener struct
Same pattern as TransportEventsListener:
- Fields: `listener *C.z_owned_link_events_listener_t`, `receiver <-chan LinkEvent`
- `Handler()`, `Drop()`, `Undeclare()`

## LinkEventsListenerOptions
- `History bool`
- `Transport *Transport` — optional filter; when set, only receive events for links of this transport. Use `z_transport_clone` to clone the filter transport into the C options.

## InfoLinksOptions
- `Transport *Transport` — optional filter for the synchronous `Links()` method

## Session methods
Synchronous:
- `Links(options *InfoLinksOptions) ([]Link, error)` — follows `PeersZId()` pattern with `z_info_links`. The C function takes an optional options struct for transport filtering.

Event listeners:
- `DeclareLinkEventsListener(handler Handler[LinkEvent], options *LinkEventsListenerOptions) (LinkEventsListener, error)`
- `DeclareBackgroundLinkEventsListener(closure Closure[LinkEvent], options *LinkEventsListenerOptions) error`

## Analog
- Transport type in `zenoh/transport.go` (previous step) — same ownership and listener patterns
- `zenoh/config.go:Get()` — pattern for extracting C strings to Go strings
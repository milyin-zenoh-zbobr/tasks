## What
Add C bridge support for the connectivity API in `zenoh/zenoh_cgo.h` and `zenoh/zenoh_cgo.c`.

## Why
The connectivity API events (transport events, link events) use C closures that receive loaned pointers. Like the existing subscriber/queryable/get patterns, we need C callback functions that extract data from loaned pointers before calling into Go. However, unlike samples/queries which need complex data extraction, transport and link events are simpler — the C API provides `z_take_from_loaned` to clone owned copies from loaned pointers. For the synchronous `z_info_transports`/`z_info_links` closures, a similar pattern to `zenohZIdCallback` in `session.go` is needed.

## Changes in zenoh_cgo.h
Add extern declarations for 4 Go-exported callback functions:
- `zenohTransportEventsCallback(z_loaned_transport_event_t*, void*)` — transport event listener callback
- `zenohTransportEventsDrop(void*)` — transport event listener drop
- `zenohLinkEventsCallback(z_loaned_link_event_t*, void*)` — link event listener callback
- `zenohLinkEventsDrop(void*)` — link event listener drop

Also add for synchronous transport/link iteration (used by `Transports()` and `Links()`):
- `zenohTransportCallback(z_loaned_transport_t*, void*)` — transport iteration callback
- `zenohTransportDrop(void*)` — transport iteration drop
- `zenohLinkCallback(z_loaned_link_t*, void*)` — link iteration callback
- `zenohLinkDrop(void*)` — link iteration drop

## Changes in zenoh_cgo.c
No C-side callback wrappers needed for this API. Unlike the subscriber pattern where `zenohSubscriberCallback` in C extracts sample data into a struct before calling Go, the transport/link event callbacks can be handled directly in Go since the event types have simple accessors (kind, transport/link) that can be called from Go via CGo. Follow the simpler MatchingListener pattern where the Go callback directly receives the C pointer.

## Analog
- `zenohMatchingListenerCallback`/`zenohMatchingListenerDrop` pattern in zenoh_cgo.h (lines 133-136) — these are extern Go functions declared in the C header, used with `z_closure_matching_status`
- `zenohZIdCallback`/`zenohZIdDrop` in session.go — for the synchronous iteration closures
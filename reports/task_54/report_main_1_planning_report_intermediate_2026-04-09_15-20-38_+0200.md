## Corrected Plan: Implement Connectivity API 2

### Key correction from user feedback

In the previous plan, step 5 said "Drop it after the C call completes" — this was wrong. The `cOpts.transport` field in `z_info_links_options_t` and `z_link_events_listener_options_t` uses **move semantics**: after `cOpts.transport = C.z_transport_move(&ownedTransport)`, ownership is transferred to the C struct. The C function (`z_info_links`, `z_declare_link_events_listener`, etc.) takes ownership and drops the transport internally. Calling `z_transport_drop` afterwards would be a double-free.

### Summary of changes

1. **zenoh-c submodule**: Switch to `milyin-zenoh-zbobr/zenoh-c` at branch `zbobr_fix-60-transport-from-fields` (provides `zc_internal_create_transport`). Document original URL for easy rollback.

2. **Copy base from connectivity_api branch**: `transport.go`, `link.go`, `zenoh_cgo.h`, `z_info.go`, `connectivity_test.go`.

3. **Transport → pure Go struct**: Replace `*C.z_owned_transport_t` with flat fields (`zId`, `whatAmI`, `isQos`, `isMulticast`, `isShm`). Remove `Drop()`/`Clone()`. Add `extractTransportSnapshot()` helper. Update `zenohTransportCallback` to use it.

4. **Link → pure Go struct**: Replace `*C.z_owned_link_t` with flat fields (same as LinkEvent minus kind). Remove `Drop()`/`Clone()`. Add `extractLink()` helper. Update `zenohLinkCallback` to use it.

5. **Options**: Change `*Transport` → `option.Option[Transport]` in `LinkEventsListenerOptions` and `InfoLinksOptions`.

6. **Filtering with zc_internal_create_transport (move semantics)**: Create owned transport from Go fields, move it into cOpts, call C function. **No drop afterwards** — C takes ownership.

7. **Examples/tests**: Remove all `.Drop()` calls on Transport/Link values.

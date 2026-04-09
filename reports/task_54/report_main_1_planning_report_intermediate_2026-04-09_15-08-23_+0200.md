## Proposed Implementation Plan

### Overview
Copy the `connectivity_api` upstream branch as the base, then apply two key changes:
1. Make `Transport` and `Link` pure Go value structs (no C pointers, no `Drop()`) — same pattern as `TransportEvent` and `LinkEvent`
2. Use `option.Option[Transport]` instead of `*Transport` in options structs

### Key Steps

**1. Update zenoh-c submodule**
- Point submodule to `milyin-zenoh-zbobr/zenoh-c` at branch `zbobr_fix-60-transport-from-fields` (has `zc_internal_create_transport`)
- Document easy way to switch back to official zenoh-c

**2. Redesign `Transport` as pure Go struct (transport.go)**
- Replace `*C.z_owned_transport_t` with flat fields: `zId`, `whatAmI`, `isQos`, `isMulticast`, `isShm`
- Remove `Drop()` and `Clone()` methods
- Add `extractTransportSnapshot()` helper (mirrors existing `extractLinkSnapshot`)
- Update `zenohTransportCallback` to use it

**3. Redesign `Link` as pure Go struct (link.go)**
- Replace `*C.z_owned_link_t` with flat fields (same as `LinkEvent`)
- Remove `Drop()` and `Clone()` methods
- Update `zenohLinkCallback` to use existing `extractLinkSnapshot` logic

**4. Use `option.Option[Transport]` in options (link.go)**
- `LinkEventsListenerOptions.Transport`: `*Transport` → `option.Option[Transport]`
- `InfoLinksOptions.Transport`: `*Transport` → `option.Option[Transport]`

**5. Use `zc_internal_create_transport` for filtering**
- When transport filter is set, call `zc_internal_create_transport(zid, whatami, is_qos, is_multicast)` to reconstruct a temporary C transport for the filter
- Drop it after the C call completes

**6. Update example (z_info.go) and tests (connectivity_test.go)**
- Remove all `.Drop()` calls on Transport/Link values
- Update option fields from pointer to `option.Some(...)`

### Analog
`TransportEvent` and `LinkEvent` — the existing "native Go" structs that serve as the direct template for the redesigned `Transport` and `Link`.

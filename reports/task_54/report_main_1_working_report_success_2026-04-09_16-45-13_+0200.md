# Connectivity API 2 Implementation — Complete

## Summary

All 7 checklist items completed in 2 commits on branch `zbobr_fix-54-implement-connectivity-api-2`.

## Commit 1: zenoh-c submodule update (9222fcd)
- Updated `.gitmodules` to point to `milyin-zenoh-zbobr/zenoh-c` at branch `zbobr_fix-60-transport-from-fields`
- Added comment with original URL for easy rollback: `# To switch back to official: url = https://github.com/eclipse-zenoh/zenoh-c.git`
- Submodule now at commit `d0f34911` which includes `zc_internal_create_transport`

## Commit 2: Full connectivity API implementation (14c3c98)

### transport.go (new file)
- `Transport` is now a pure Go struct with fields: `zId`, `whatAmI`, `isQos`, `isMulticast`, `isShm`
- No `Drop()` or `Clone()` methods — fully GC-managed
- `extractTransportSnapshot(loaned *C.z_loaned_transport_t) Transport` helper
- `zenohTransportCallback` uses `extractTransportSnapshot` instead of cloning C object
- All session methods: `Transports()`, `DeclareTransportEventsListener`, `DeclareBackgroundTransportEventsListener`

### link.go (new file)
- `Link` is a pure Go struct matching `LinkEvent` fields (without `kind`)
- No `Drop()` or `Clone()` methods
- `extractLink(loaned *C.z_loaned_link_t) Link` helper; `extractLinkSnapshot` reuses it
- `zenohLinkCallback` uses `extractLink` instead of cloning
- `LinkEventsListenerOptions.Transport` and `InfoLinksOptions.Transport` are `option.Option[Transport]`
- `buildCTransport(Transport) C.z_owned_transport_t` reconstructs a C transport from Go fields using `zc_internal_create_transport`; C takes ownership via move semantics (no drop after)
- All session methods updated to use `option.IsSome()` / `option.Unwrap()` checks

### zenoh_cgo.h / zenoh_cgo.c changes
- Added `zc_cgo_transport_is_shm` wrapper that conditionally calls `z_transport_is_shm` only when `Z_FEATURE_SHARED_MEMORY` is defined, returning `false` otherwise (avoids compile error when SHM not available)
- Added extern declarations for transport/link callbacks

### examples/z_info/z_info.go
- Removed `tr.Drop()` and `l.Drop()` calls (Transport and Link are plain Go structs now)

### tests/connectivity_test.go (new file)
- Full test suite covering: transport list, link list, filtered links, transport/link events, history, transport filter listeners, accessors, event snapshots, undeclare, background listeners
- No `Drop()` calls on Transport or Link values
- Uses `option.Some(transport)` for filter options

## Key design decisions
- `unsafe.Pointer` cast used for `whatami` field assignment in `buildCTransport` because CGO exposes the enum struct field as Go's `uint32` which is incompatible with `C.z_whatami_t` in direct assignment
- `isShm` field is always populated via the wrapper (returns false without SHM feature)
- All builds pass: `go build ./...` and `go vet ./...` produce no errors

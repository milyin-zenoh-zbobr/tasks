## Review Fixes Applied

### 1. Link.Group() and Link.AuthIdentifier() string leak (Medium severity)
**File:** `zenoh/link.go`

Added `defer C.zc_cgo_string_drop(&s)` immediately after obtaining the owned string, before the `z_internal_string_check` early-return. This ensures the owned C string is always released regardless of whether it's valid.

### 2. TransportEvent/LinkEvent memory leak (High severity)
**Files:** `zenoh/transport.go`, `zenoh/link.go`, `tests/connectivity_test.go`, `examples/z_info/z_info.go`

Converted both event types from C-object wrappers to pure Go snapshots. The callbacks now extract all fields directly from the loaned C pointers (no clone needed) and build plain Go structs:

- **TransportEvent** now holds: Kind, ZId, WhatAmI, IsQos, IsMulticast, IsShm — with direct accessor methods
- **LinkEvent** now holds: Kind, ZId, Src, Dst, Group, Mtu, IsStreamed, Interfaces, AuthIdentifier, Priorities, Reliability — with direct accessor methods and a helper `extractLinkSnapshot()` function

This eliminates per-event C resource leaks entirely since there are no owned C objects in events.

Updated tests and example to use `evt.ZId()` / `evt.Src()` style instead of `evt.Transport().ZId()` / `evt.Link().ZId()`.

### Commits
1. `2f0fad0` — Fix memory leak in Link.Group() and Link.AuthIdentifier()
2. `1687e08` — Convert TransportEvent to pure Go snapshot
3. `dd3c991` — Convert LinkEvent to pure Go snapshot
4. `9e6fb46` — Update tests and example for snapshot-based event API

### Note
Build environment lacks zenoh-c headers so compilation couldn't be verified locally, but all changes follow the exact same C API patterns used by the existing Link and Transport types.
The implementation is complete. Here's a summary of what was done:

**`zenoh/transport.go`** — `TransportEvent` now wraps a single `Transport` field with a `Transport()` accessor, removing 5 duplicated fields and methods.

**`zenoh/link.go`** — `LinkEvent` now wraps a single `Link` field with a `Link()` accessor, removing 10 duplicated fields and methods. Also fixed a pre-existing CGO bug: `buildCTransport` now allocates on the C heap so `z_transport_move(&owned)` stores a C pointer (not a Go stack pointer) inside `cOpts`, preventing the "Go pointer to unpinned Go pointer" panic.

**`tests/connectivity_test.go`** and **`examples/z_info/z_info.go`** — all event field accesses updated to go through `evt.Transport().xxx()` and `evt.Link().xxx()`.

All tests pass.
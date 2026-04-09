Copy the following files from the upstream `connectivity_api` branch (https://github.com/eclipse-zenoh/zenoh-go/tree/connectivity_api) as the starting point:

- `zenoh/transport.go` — Transport, TransportEvent, TransportEventsListener, session methods
- `zenoh/link.go` — Link, LinkEvent, LinkEventsListener, session methods  
- `zenoh/zenoh_cgo.h` — C declarations for transport/link callbacks
- `zenoh/zenoh_cgo.c` — C wrappers if any
- `examples/z_info.go` — usage example showing transports and links
- `tests/connectivity_test.go` — test suite

**Why**: The upstream branch has the full connectivity API implemented; we're using it as a base and applying specific modifications on top rather than starting from scratch.

**Note**: Do NOT yet remove Drop()/Clone() or change option types — that's done in the following checklist items. Just get the base files into the repo first to confirm they compile.
Plan is ready for review. The implementation covers 5 steps:

1. **C bridge additions** — 8 callback declarations in `zenoh_cgo.h`
2. **Transport type** (`transport.go`) — Transport, TransportEvent, TransportEventsListener + session methods
3. **Link type** (`link.go`) — Link, LinkEvent, LinkEventsListener + session methods with optional transport filtering
4. **Test suite** (`connectivity_test.go`) — 9 tests using explicit TCP peer connections
5. **Example extension** (`z_info.go`) — transport/link listing + event monitoring

Primary analog: **MatchingListener** pattern from `matching.go`.
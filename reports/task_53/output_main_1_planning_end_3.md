The plan is ready for your review. It covers:

- **C bridge layer**: 4 data structs + 4 callback functions in zenoh_cgo.h/c that clone transport/link from loaned pointers (following the subscriber extraction pattern)
- **Transport types** in `transport.go`: Transport (wrapping owned C struct), TransportEvent, TransportEventsListener (following MatchingListener pattern)
- **Link types** in `link.go`: Link (wrapping owned C struct), LinkEvent, LinkEventsListener (same pattern)
- **Session methods**: `Transports()`/`Links()` (PeersZId pattern) + 4 event listener declare methods (MatchingListener pattern)
- **9 tests** in `connectivity_test.go` modeled on `matching_test.go`
- **z_info example** extended with transport/link listing
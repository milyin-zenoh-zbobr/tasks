## Plan Summary

The connectivity API implementation follows the MatchingListener pattern as the primary analog, with PeersZId() for synchronous queries.

### Key Design Decisions
1. **Both Transport and Link wrap C owned structures** — consistent ownership model
2. **Event listeners use MatchingListener pattern** — Handler/Drop/Undeclare, channel-based and closure-based variants
3. **Event kind uses SampleKind** — PUT=connected/added, DELETE=disconnected/removed (matching C API design)
4. **No complex C bridge data extraction** — unlike subscribers, transport/link event callbacks use direct CGo calls since the types are simpler
5. **Tests use explicit TCP peer-to-peer connections** — necessary to control connect/disconnect timing for event testing

### Implementation Steps
1. C bridge: 8 callback declarations in zenoh_cgo.h
2. Transport type + session methods in transport.go
3. Link type + session methods in link.go  
4. 9 tests in connectivity_test.go (modeled on matching_test.go + z_api_info.c)
5. z_info example extension with event monitoring
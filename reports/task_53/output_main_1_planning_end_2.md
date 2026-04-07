The plan is ready for review. Key additions since the last iteration:

**Test suite** (`tests/connectivity_test.go`) — 9 test cases modeled on zenoh-c's `z_api_info.c`:
- Transports/links query with ZId verification
- Filtered links by transport
- Transport and link events (connect/disconnect PUT/DELETE)
- History mode for both event types
- Background listener variants
- Link events with transport filter

**z_info example extension** — Following `z_info.c` pattern:
- Print all transports with properties (ZId, WhatAmI, QoS, multicast)
- Print all links with properties (ZId, src, dst, MTU, streaming, interfaces, priorities, reliability)
- Event monitoring with CTRL-C shutdown

Tests use isolated session pairs (router + peer on explicit TCP endpoints, multicast scouting disabled) following the pattern from `advanced_pub_sub_test.go`.
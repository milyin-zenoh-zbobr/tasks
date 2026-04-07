## What
Create `tests/connectivity_test.go` with tests modeled on `tests/matching_test.go` structure but using the connectivity API. Tests are modeled on `z_api_info.c` test scenarios from the zenoh-c PR.

## Why
The tests validate the full connectivity API: synchronous queries, event listeners with and without history, background listeners, and transport filtering.

## Test setup
Unlike matching tests that use `NewConfigDefault()` (which uses scouting), connectivity tests need explicit peer-to-peer connections with known endpoints to test transport connect/disconnect events. Use `Config.InsertJson5` to set:
- Session 1: `listen/endpoints` = `["tcp/127.0.0.1:PORT"]`, `scouting/multicast/enabled` = `"false"`
- Session 2: `connect/endpoints` = `["tcp/127.0.0.1:PORT"]`, `scouting/multicast/enabled` = `"false"`
Use unique ports per test to avoid conflicts. Set mode to `"peer"` for both.

## Test cases (9 tests)

1. **TestTransportsList** — Open two connected sessions. Call `Transports()` on session 1. Assert exactly 1 transport whose ZId matches session 2's ZId.

2. **TestLinksList** — Same setup. Call `Links(nil)` on session 1. Assert exactly 1 link whose ZId matches session 2's ZId.

3. **TestLinksFilteredByTransport** — Same setup. Get transports from session 1, then call `Links(&InfoLinksOptions{Transport: &transport})`. Assert results match. Call with a different transport (from session 2's perspective) and assert empty.

4. **TestTransportEventsListener** — Open session 1 with listener endpoint. Declare `TransportEventsListener` with `History: false`. Then open session 2 connecting to session 1. Wait, assert 1 PUT event with matching ZId. Close session 2. Wait, assert 1 DELETE event. Follow `test_transport_events()` from z_api_info.c.

5. **TestTransportEventsListenerWithHistory** — Open both sessions connected. Then declare `TransportEventsListener` with `History: true`. Assert receives PUT event for existing transport.

6. **TestBackgroundTransportEventsListener** — Same as test 4 but use `DeclareBackgroundTransportEventsListener` with a Closure that appends to a slice. Follow `TestPublisherBackgroundMatchingListener` pattern.

7. **TestLinkEventsListener** — Mirror of test 4 for links.

8. **TestLinkEventsListenerWithHistory** — Mirror of test 5 for links.

9. **TestLinkEventsListenerWithTransportFilter** — Declare link events listener with transport filter. Assert only events for matching transport are received.

## Analog
- `tests/matching_test.go` — test structure, assertion patterns, channel-based vs closure-based listener testing
- `z_api_info.c` test file from zenoh-c PR — test scenarios and expected behaviors
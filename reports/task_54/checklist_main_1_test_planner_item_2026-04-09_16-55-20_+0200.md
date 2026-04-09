# Test: TestLinkEventsListenerTransportFilterForwardEvents

## Location
`tests/connectivity_test.go`

## What to test
`TestLinkEventsListenerWithTransportFilter` only exercises the transport filter when `History: true`. The filter in `DeclareLinkEventsListener` (`zenoh/link.go:393-397`) should also apply to forward events. This path is untested.

## Test steps
1. Open listener session `s1`.
2. Connect `s2` to s1 and wait for connection.
3. Get `s1.Transports()` — this is the transport for s2.
4. Declare link events listener on s1 with `Transport: option.Some(transports[0])` but **no history**.
5. Connect a third session `s3` on a different port/same address (or disconnect+reconnect s2 to trigger a new event). Actually: connect `s3` to the same listener — this creates a new transport, so its links should be filtered out.
6. Disconnect `s2` and reconnect to trigger a DELETE+PUT event pair for the **matching** transport.
7. Assert only events from the filtered transport's ZId are delivered; events from s3's transport are not.

**Alternative simpler approach (preferred):**
1. Open listener `s1`.
2. Declare link events listener with a dummy/zero `option.Some(Transport{})` filter (no matching transport).
3. Connect `s2`.
4. Sleep 200ms.
5. Assert **0 events** received — the non-matching transport filter drops all events.
6. Cross-check: declare a second listener with no filter and confirm it **does** receive the event.

## Port suggestions
17969 (s1 listener), 17970 (second listener for cross-check if needed)

## Why
Validates that the transport filter in `DeclareLinkEventsListener` correctly suppresses forward link events that don't match the specified transport, not just historical ones. This is a distinct behavioral contract.
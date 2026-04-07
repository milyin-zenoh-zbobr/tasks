# Test: TestBackgroundLinkEventsListener

## Goal
`DeclareBackgroundLinkEventsListener` is fully untested. Mirror the existing `TestBackgroundTransportEventsListener` test for links.

## Setup
- `openListenerSession(t, <port>)` → s1
- Declare background listener with a `Closure[LinkEvent]` that appends to a local slice.
- `openConnectorSession(t, <port>)` → s2, `time.Sleep(500ms)`
- assert `len(events) == 1` and `events[0].Kind() == SampleKindPut`
- `s2.Drop()`, `time.Sleep(500ms)`
- assert `len(events) == 2` and `events[1].Kind() == SampleKindDelete`

## Why this matters
The background listener uses `z_declare_background_link_events_listener` which is a separate C function call path than the foreground listener. Without this test, any mis-binding (wrong function pointer, wrong option struct) would go undetected.

## File
`tests/connectivity_test.go`

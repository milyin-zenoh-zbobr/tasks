# Test: TestListenerUndeclare (two sub-cases)

## Goal
`Undeclare()` is a distinct code path from `Drop()` — it calls `z_undeclare_*` and returns an error code. This path is currently not tested.

## Sub-test 1: TestTransportEventsListenerUndeclare
- `openListenerSession(t, <port>)` → s1
- `listener, err := s1.DeclareTransportEventsListener(...)` → assert no error
- `err = listener.Undeclare()` → assert `err == nil`
- `openConnectorSession(t, <port>)` → s2, `time.Sleep(200ms)`
- `len(listener.Handler())` → `0` (no events after undeclare)

## Sub-test 2: TestLinkEventsListenerUndeclare
- Same pattern using `DeclareLinkEventsListener` and `LinkEventsListener.Undeclare()`

## Why this matters
`Undeclare()` calls `z_undeclare_*` rather than plain `z_*_drop`. If the C binding is wrong or the listener is in a bad state, this is where it would fail. Testing it ensures the Go wrapper correctly passes the error return value.

## File
`tests/connectivity_test.go`

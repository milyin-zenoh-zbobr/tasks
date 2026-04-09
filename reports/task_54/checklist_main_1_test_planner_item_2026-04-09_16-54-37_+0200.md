# Test: TestBackgroundTransportEventsListenerWithHistory

## Location
`tests/connectivity_test.go`

## What to test
The `DeclareBackgroundTransportEventsListener` function has an untested `options != nil` branch (`zenoh/transport.go:239-245`) that constructs `cOpts` and sets `history = true` before calling C. The existing `TestBackgroundTransportEventsListener` passes `nil` options.

## Test steps
1. Open connected pair `(s1, s2)` before declaring the listener (so a transport already exists).
2. Call `s1.DeclareBackgroundTransportEventsListener(closure, &zenoh.TransportEventsListenerOptions{History: true})`.
3. Sleep 200ms to allow history delivery.
4. Assert the closure received exactly **1 event** with `Kind() == SampleKindPut` and `ZId()` matching `s2.ZId()`.
5. Defer `s1.Drop()` and `s2.Drop()`.

## Port suggestion
17967

## Why
Validates the `options != nil` code path including history flag propagation to C in the background variant of the transport events listener API.
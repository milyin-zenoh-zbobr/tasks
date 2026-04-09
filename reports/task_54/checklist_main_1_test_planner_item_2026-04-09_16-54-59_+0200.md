# Test: TestBackgroundLinkEventsListenerWithHistoryAndFilter

## Location
`tests/connectivity_test.go`

## What to test
`DeclareBackgroundLinkEventsListener` has two untested branches: the `options != nil` path and the `options.Transport.IsSome()` transport filter path (`zenoh/link.go:418-428`). The existing `TestBackgroundLinkEventsListener` passes `nil` options.

## Test steps
1. Open connected pair `(s1, s2)`.
2. Call `s1.Transports()` to get the transport for s2.
3. Call `s1.DeclareBackgroundLinkEventsListener(closure, &zenoh.LinkEventsListenerOptions{History: true, Transport: option.Some(transport)})`.
4. Sleep 200ms.
5. Assert the closure received exactly **1 event** with `Kind() == SampleKindPut` and `ZId()` matching `s2.ZId()`.
6. Defer drops.

## Port suggestion
17968

## Why
Validates both the `history` and `transport` option code paths in the background link events listener, exercising `buildCTransport` round-trip and C move semantics from the background API entry point.
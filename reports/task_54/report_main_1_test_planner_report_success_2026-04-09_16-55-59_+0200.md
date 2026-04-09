# Test Planning Report: Connectivity API 2

## Summary

The existing `tests/connectivity_test.go` provides good coverage of the happy path for all major API methods (15 test functions). After reviewing the implementation (`zenoh/transport.go`, `zenoh/link.go`) against the tests, 4 untested code paths were identified.

## Untested Code Paths Found

### 1. Background listeners — `options != nil` branch
Both `DeclareBackgroundTransportEventsListener` and `DeclareBackgroundLinkEventsListener` have an `options != nil` branch that constructs `cOpts` and sets options flags before calling C. The existing background tests pass `nil` options, leaving this branch unexercised.

### 2. Transport filter on forward events
`TestLinkEventsListenerWithTransportFilter` only tests history=true. The transport filter in `DeclareLinkEventsListener` also applies to new (non-historical) link events — this code path (`zenoh/link.go:393-397`) is not validated in a forward-event scenario.

### 3. Empty list cases
`Transports()` and `Links()` on an unconnected session are not tested. The zero-result case validates the closure-based collection helpers when the C iteration callback is never invoked.

## Checklist Items Added

- **ctx_rec_13**: `TestBackgroundTransportEventsListenerWithHistory` — `options != nil` + history=true in DeclareBackgroundTransportEventsListener
- **ctx_rec_14**: `TestBackgroundLinkEventsListenerWithHistoryAndFilter` — `options != nil` + History + Transport filter in DeclareBackgroundLinkEventsListener
- **ctx_rec_15**: `TestLinkEventsListenerTransportFilterForwardEvents` — transport filter suppresses non-matching forward link events
- **ctx_rec_16**: `TestEmptyTransportsAndLinksLists` — Transports() and Links() return empty slices with no error on an isolated session

## Tests NOT Added (Rationale)

- **`option.None` explicit test**: `InfoLinksOptions{Transport: option.None()}` follows the same code path as `nil` options — already covered by `TestLinksList`.
- **Multiple transports**: Not a new API contract; the collection callback mechanism is already validated by the single-transport case.
- **Transport value copy semantics**: This is a Go language guarantee, not an API contract to test.
- **Receiver consistency (value vs pointer)**: A style issue noted in review, not a behavioral contract.

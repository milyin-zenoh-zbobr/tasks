# Test: TestEmptyTransportsAndLinksLists

## Location
`tests/connectivity_test.go`

## What to test
`Session.Transports()` and `Session.Links()` on a session with no peers connected. The closure-based collection helpers return `[]Transport{}` / `[]Link{}` when the C iteration callback is never called. This zero-result case is not explicitly tested.

## Test steps
1. Open a single peer session `s` with listen address only (use `openListenerSession`), no connector.
2. Call `transports, err := s.Transports()`.
3. Assert `err == nil` and `len(transports) == 0`.
4. Call `links, err := s.Links(nil)`.
5. Assert `err == nil` and `len(links) == 0`.
6. Defer `s.Drop()`.

## Port suggestion
17971

## Why
Validates that the callback-based collection helpers correctly handle the empty-collection case without crashing or returning spurious errors. Also confirms `Links` and `Transports` are usable immediately after open before any peers connect.
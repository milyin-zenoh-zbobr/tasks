# Test: TestLinkAccessors

## Goal
Verify all `Link` accessor methods return correct values for a unicast TCP link.

## Setup
Use `openConnectedPair(t, <port>)`.  
Call `s1.Links(nil)` to get `links[0]`.

## Assertions
- `links[0].Src()` → non-empty string (local TCP endpoint, e.g. `"tcp/127.0.0.1:NNNNN"`)
- `links[0].Dst()` → non-empty string (remote TCP endpoint)
- `links[0].Mtu()` → `> 0`
- `links[0].IsStreamed()` → `true` (TCP is a streamed transport)
- `links[0].Interfaces()` → slice (may be empty, but should not panic; `len >= 0`)
- `links[0].Group()` → `""` (unicast link has no group)
- `links[0].AuthIdentifier()` → `""` (no auth configured)
- `links[0].Priorities()` → `(_, _, ok)` – just call and ensure no panic
- `links[0].Reliability()` → `(_, ok)` – just call and ensure no panic

### Clone sub-test
- `clone := links[0].Clone()`
- `clone.Src()` == `links[0].Src()` and `clone.ZId()` == `links[0].ZId()`
- `clone.Drop()` does not corrupt `links[0]` (call `links[0].Src()` again and verify same value)

## File
`tests/connectivity_test.go`

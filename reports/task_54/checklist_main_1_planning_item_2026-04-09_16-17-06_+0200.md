Update `examples/z_info.go` and `tests/connectivity_test.go` to work with the new pure Go Transport and Link types.

**What to change in examples/z_info.go**:
- Remove all `.Drop()` calls on `Transport` and `Link` values (they are now plain Go structs, GC-managed)
- The struct fields are directly accessible (ZId(), WhatAmI(), IsQos(), IsMulticast() are still methods)

**What to change in tests/connectivity_test.go**:
- Remove `.Drop()` calls on Transport/Link values
- Update any code that passes a transport filter: change from `&transport` to `option.Some(transport)` (or similar option construction) in `InfoLinksOptions` and `LinkEventsListenerOptions`
- Ensure `TestLinksFilteredByTransport` still exercises the filtering path correctly

**Why**: After making Transport and Link pure Go structs, Drop() no longer exists and will fail to compile. The option type change also requires call-site updates.

**Verification**: `go build ./...` and `go vet ./...` should produce no errors. All connectivity tests should pass.
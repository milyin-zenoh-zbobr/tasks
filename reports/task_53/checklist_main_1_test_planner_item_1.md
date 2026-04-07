## Extend event listener tests with snapshot field validation

### TestTransportEventsListener — after receiving PUT event, add:
```go
assert.Equal(t, zenoh.WhatAmIPeer, evt.WhatAmI())
assert.True(t, evt.IsQos())
assert.False(t, evt.IsMulticast())
```

### TestLinkEventsListener — after receiving PUT event, add:
```go
assert.Contains(t, evt.Src(), "tcp/127.0.0.1")
assert.Contains(t, evt.Dst(), "tcp/127.0.0.1")
assert.Greater(t, evt.Mtu(), uint16(0))
assert.True(t, evt.IsStreamed())
assert.NotEmpty(t, evt.Interfaces())
```

File: `tests/connectivity_test.go`
These validate that `extractLinkSnapshot` and the transport event snapshot code correctly copy all fields from the C event into the pure Go snapshot structs.
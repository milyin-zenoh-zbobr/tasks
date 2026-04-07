## Extend synchronous query tests with accessor validation

### TestTransportsList — add after existing ZId assertion:
```go
assert.Equal(t, zenoh.WhatAmIPeer, transports[0].WhatAmI())
assert.True(t, transports[0].IsQos())
assert.False(t, transports[0].IsMulticast())
```

### TestLinksList — add after existing ZId assertion:
```go
assert.Contains(t, links[0].Src(), "tcp/127.0.0.1")
assert.Contains(t, links[0].Dst(), "tcp/127.0.0.1")
assert.Greater(t, links[0].Mtu(), uint16(0))
assert.True(t, links[0].IsStreamed()) // TCP is streamed
assert.NotEmpty(t, links[0].Interfaces())
```

File: `tests/connectivity_test.go`
These assertions validate that the C-to-Go bridge correctly extracts each field for a known TCP peer-to-peer connection.
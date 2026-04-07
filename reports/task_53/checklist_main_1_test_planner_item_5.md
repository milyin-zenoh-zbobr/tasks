# Test: TestTransportAccessors

## Goal
Verify all Transport accessor methods return sensible values for a unicast TCP peer-mode transport.

## Setup
Use `openConnectedPair(t, <port>)` to get s1 (listener) and s2 (connector) over TCP.  
Call `s1.Transports()` to get `transports[0]`.

## Assertions
- `transports[0].WhatAmI()` → should equal `WhatAmIPeer` (both sessions open as peer mode)
- `transports[0].IsMulticast()` → `false` (unicast TCP)
- `transports[0].IsQos()` → can be `true` or `false`; assert no panic and the value is a valid bool (i.e., just call it; if QoS default changes we don't want a hardcoded assertion)
- `transports[0].IsShm()` → `false` (SHM not configured)
- `transports[0].Clone()` → clone's `ZId()` matches original; Drop clone without affecting original; original `ZId()` still matches `s2.ZId()`

## File
`tests/connectivity_test.go`

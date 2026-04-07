# Test: TestTransportEventAccessors

## Goal
Verify that the `TransportEvent` snapshot captures all transport fields correctly, not just `Kind()` and `ZId()`.

## Setup
Use `openListenerSession(t, <port>)` to get s1.  
Declare a `DeclareTransportEventsListener` with a FifoChannel.  
`openConnectorSession(t, <port>)` to trigger a PUT event.  
`time.Sleep(500ms)` to wait.  
Read one event from the channel.

## Assertions
On the received `TransportEvent`:
- `evt.Kind()` → `SampleKindPut`
- `evt.WhatAmI()` → `WhatAmIPeer`
- `evt.IsMulticast()` → `false`
- `evt.IsQos()` → any bool value (just confirm no panic / accessible)
- `evt.IsShm()` → `false`

These confirm the snapshot extraction path (`zenohTransportEventsCallback`) copies all fields from the loaned C object.

## File
`tests/connectivity_test.go`

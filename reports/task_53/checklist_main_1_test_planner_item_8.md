# Test: TestLinkEventSnapshotFields

## Goal
Confirm that `LinkEvent` fields extracted in the `extractLinkSnapshot` callback match the corresponding `Link` fields returned by synchronous `Links()` for the same connection.

## Setup
Use `openListenerSession(t, <port>)` for s1.  
Declare `DeclareLinkEventsListener` with `History: false` (default).  
`openConnectorSession(t, <port>)` to trigger a PUT event.  
`time.Sleep(500ms)`.  
Read event from channel → `evt LinkEvent`.  
Also call `s1.Links(nil)` → `links[0]`.

## Assertions
Compare snapshot event fields against synchronous link:
- `evt.ZId()` == `links[0].ZId()`
- `evt.Src()` == `links[0].Src()`  (non-empty)
- `evt.Dst()` == `links[0].Dst()`  (non-empty)
- `evt.Mtu()` == `links[0].Mtu()`  (> 0)
- `evt.IsStreamed()` == `links[0].IsStreamed()` (true for TCP)
- `evt.Interfaces()` deep equals `links[0].Interfaces()` 
- `evt.Group()` == `links[0].Group()` (empty for unicast)
- `evt.Kind()` == `SampleKindPut`

This validates the snapshot extraction path in `extractLinkSnapshot` is consistent with the synchronous `zenohLinkCallback` path.

## File
`tests/connectivity_test.go`

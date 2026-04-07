## Add missing background link events listener test

Add `TestBackgroundLinkEventsListener` following the same pattern as `TestBackgroundTransportEventsListener`:

```go
func TestBackgroundLinkEventsListener(t *testing.T) {
    s1 := openListenerSession(t, PORT)
    defer s1.Drop()

    var events []zenoh.LinkEvent
    err := s1.DeclareBackgroundLinkEventsListener(
        zenoh.Closure[zenoh.LinkEvent]{
            Call: func(evt zenoh.LinkEvent) { events = append(events, evt) },
        },
        nil,
    )
    require.NoError(t, err)

    s2 := openConnectorSession(t, PORT)
    time.Sleep(500 * time.Millisecond)
    assert.Equal(t, 1, len(events))
    assert.Equal(t, zenoh.SampleKindPut, events[0].Kind())

    s2.Drop()
    time.Sleep(500 * time.Millisecond)
    assert.Equal(t, 2, len(events))
    assert.Equal(t, zenoh.SampleKindDelete, events[1].Kind())
}
```

File: `tests/connectivity_test.go`
Use a unique port number to avoid conflicts with other tests.
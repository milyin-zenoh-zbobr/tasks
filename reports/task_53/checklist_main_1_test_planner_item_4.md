## Add Undeclare test

```go
func TestTransportEventsListenerUndeclare(t *testing.T) {
    s1 := openListenerSession(t, PORT)
    defer s1.Drop()

    listener, err := s1.DeclareTransportEventsListener(zenoh.NewFifoChannel[zenoh.TransportEvent](16), nil)
    require.NoError(t, err)

    err = listener.Undeclare()
    assert.NoError(t, err)
}
```

File: `tests/connectivity_test.go`
Validates the Undeclare() code path returns no error. Currently only Drop() is exercised via defer.
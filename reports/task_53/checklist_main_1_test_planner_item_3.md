## Add clone lifecycle tests

### TestTransportClone
```go
func TestTransportClone(t *testing.T) {
    s1, s2 := openConnectedPair(t, PORT)
    defer s1.Drop()
    defer s2.Drop()

    transports, err := s1.Transports()
    require.NoError(t, err)
    require.Equal(t, 1, len(transports))

    clone := transports[0].Clone()
    // Both should have same ZId
    assert.Equal(t, transports[0].ZId().String(), clone.ZId().String())
    // Drop original, clone should still work
    transports[0].Drop()
    assert.Equal(t, s2.ZId().String(), clone.ZId().String())
    clone.Drop()
}
```

### TestLinkClone
Same pattern for Link — clone, verify ZId matches, drop original, verify clone still works.

File: `tests/connectivity_test.go`
Validates that Clone() produces an independent owned copy that survives the original being dropped.
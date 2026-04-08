# Test: `new_from_fields` is equivalent to `Transport::new()` for same data

**File**: `zenoh/src/api/info.rs` — same `#[cfg(test)] mod tests` block

**Feature gate**: `#[cfg(all(test, feature = "internal"))]`

This test validates the constructor against the authoritative production path, catching any field mis-assignment (e.g., swapping `is_qos` and `is_multicast`).

## Test body

```rust
#[test]
fn test_new_from_fields_equals_new_from_peer() {
    use zenoh_transport::TransportPeer;

    let peer = TransportPeer {
        zid: ZenohId::default(),
        whatami: WhatAmI::Router,
        is_qos: true,
        is_multicast: false,
        #[cfg(feature = "shared-memory")]
        is_shm: false,
        // remaining fields use Default
        ..Default::default()
    };

    let via_new = Transport::new(&peer, /*is_multicast=*/ false);
    let via_fields = Transport::new_from_fields(
        peer.zid.into(),
        peer.whatami,
        peer.is_qos,
        /*is_multicast=*/ false,
        #[cfg(feature = "shared-memory")]
        peer.is_shm,
    );

    assert_eq!(via_new, via_fields);
}
```

Note: If `TransportPeer` does not implement `Default`, construct it explicitly using all required fields. Check `zenoh_transport::TransportPeer` struct definition first.

**Run**:
- `cargo test -p zenoh --features internal -- info::tests::test_new_from_fields_equals_new_from_peer`
- `cargo test -p zenoh --features internal,shared-memory -- info::tests::test_new_from_fields_equals_new_from_peer`

# Test: `new_from_fields` stores all fields correctly

**File**: `zenoh/src/api/info.rs` — add `#[cfg(test)] mod tests { ... }` at the bottom

**Feature gate**: `#[cfg(all(test, feature = "internal"))]`

## Test body

```rust
#[cfg(all(test, feature = "internal"))]
mod tests {
    use super::*;
    use zenoh_protocol::core::{WhatAmI, ZenohId};

    #[test]
    fn test_new_from_fields_stores_fields() {
        let zid = ZenohId::default();
        let whatami = WhatAmI::Peer;
        let t = Transport::new_from_fields(
            zid,
            whatami,
            /*is_qos=*/ true,
            /*is_multicast=*/ false,
            #[cfg(feature = "shared-memory")]
            /*is_shm=*/ true,
        );
        assert_eq!(t.zid, zid);
        assert_eq!(t.whatami, whatami);
        assert!(t.is_qos);
        assert!(!t.is_multicast);
        #[cfg(feature = "shared-memory")]
        assert!(t.is_shm);
    }
}
```

**Run**:
- `cargo test -p zenoh --features internal -- info::tests::test_new_from_fields_stores_fields`
- `cargo test -p zenoh --features internal,shared-memory -- info::tests::test_new_from_fields_stores_fields`

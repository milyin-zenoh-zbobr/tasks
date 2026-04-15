In zenoh-jni/src/session.rs, function `declareAdvancedSubscriberViaJNI` (line 1308), change:
```rust
let session = Arc::from_raw(session_ptr);
...
std::mem::forget(session);
```
to:
```rust
let session = OwnedObject::from_raw(session_ptr);
```
This makes it consistent with `declareAdvancedPublisherViaJNI` which already uses OwnedObject::from_raw.
Also need to add `use crate::owned_object::OwnedObject;` import if not already present.
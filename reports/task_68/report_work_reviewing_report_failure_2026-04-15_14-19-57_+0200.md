## Additional finding

### Inconsistent ownership pattern in the new advanced session entrypoints
The two newly added session JNI functions use different patterns to preserve the borrowed `Session` pointer:

- `zenoh-jni/src/session.rs:1308-1369` (`Java_io_zenoh_jni_JNISession_declareAdvancedSubscriberViaJNI`) uses `Arc::from_raw(session_ptr)` and then manually balances it with `std::mem::forget(session)`.
- `zenoh-jni/src/session.rs:1429` (`Java_io_zenoh_jni_JNISession_declareAdvancedPublisherViaJNI`) uses the new `OwnedObject::from_raw(session_ptr)` helper instead.

Both approaches can work, but introducing `OwnedObject` was specifically meant to centralize this footgun-prone pattern. Leaving one of the new paths on the older manual form makes the code less consistent and easier to get wrong in follow-up edits. The advanced subscriber path should use the same `OwnedObject` helper as the advanced publisher path.
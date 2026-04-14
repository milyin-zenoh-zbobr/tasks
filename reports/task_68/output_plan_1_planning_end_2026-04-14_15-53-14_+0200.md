The plan is ready. Here's the summary:

## Plan Summary

The adversarial review identified one blocking issue in the previous plan: `zenoh-ext` in `zenoh-jni/Cargo.toml` was missing the `unstable` Cargo feature. Without it, `AdvancedPublisher`, `AdvancedSubscriber`, and related types are not exported by zenoh-ext, causing compile failure.

**The revised plan has these changes:**

1. **`zenoh-jni/Cargo.toml`** — Add `"unstable"` to `zenoh-ext` features (the root fix)

2. **`zenoh-jni/src/lib.rs`** — Add `mod owned_object`, `mod sample_callback`, and `#[cfg(feature = "zenoh-ext")] mod ext`

3. **`zenoh-jni/src/session.rs`** — Add new imports and 3 new JNI exports:
   - `Java_io_zenoh_jni_JNISession_openSessionViaJNI` (instance-method alias)
   - `Java_io_zenoh_jni_JNISession_declareAdvancedSubscriberViaJNI` (feature-gated)
   - `Java_io_zenoh_jni_JNISession_declareAdvancedPublisherViaJNI` (feature-gated)
   - Plus helper functions `prepare_publisher_builder` and `prepare_subscriber_builder`

4. **7 new files** copied verbatim from `zenoh-kotlin/zenoh-jni/src/`: `owned_object.rs`, `sample_callback.rs`, and `ext/{mod,advanced_publisher,advanced_subscriber,matching_listener,sample_miss_listener}.rs`
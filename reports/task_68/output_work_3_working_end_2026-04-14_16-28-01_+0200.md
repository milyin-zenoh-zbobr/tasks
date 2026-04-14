All work is complete. Here's a summary of what was implemented:

## Summary

Added all 16 missing JNI symbols to `zenoh-java` required for `zenoh-kotlin` compatibility:

**Root fix**: Added `"unstable"` feature to `zenoh-ext` in `Cargo.toml` — this was the blocker preventing `AdvancedPublisher`/`AdvancedSubscriber` from being available.

**New files created** (copied from zenoh-kotlin's JNI layer):
- `src/owned_object.rs` — safe Arc accessor
- `src/sample_callback.rs` — `SetJniSampleCallback` trait
- `src/ext/mod.rs`, `advanced_publisher.rs`, `advanced_subscriber.rs`, `matching_listener.rs`, `sample_miss_listener.rs` — JNI exports for advanced pub/sub

**Modified files**:
- `src/lib.rs` — added module declarations for new modules
- `src/session.rs` — added imports, `openSessionViaJNI` instance-method alias, `prepare_publisher_builder`/`prepare_subscriber_builder` helpers, and `declareAdvancedPublisherViaJNI`/`declareAdvancedSubscriberViaJNI`

**Verification**: Build succeeds and `nm` confirms all 16 required symbols are exported.
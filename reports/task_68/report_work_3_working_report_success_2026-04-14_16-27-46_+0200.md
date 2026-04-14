# Task Completion Report

## Summary

All required JNI exports for zenoh-kotlin compatibility have been added to zenoh-java's JNI crate.

## Changes Made

### 1. `zenoh-jni/Cargo.toml`
- Added `"unstable"` to `zenoh-ext` features: `["unstable", "internal"]`
- This was the root blocker: AdvancedPublisher/AdvancedSubscriber types are only exported by zenoh-ext when `unstable` is enabled.

### 2. New files created

| File | Purpose |
|---|---|
| `zenoh-jni/src/owned_object.rs` | `OwnedObject<T>`: safe Arc accessor preventing early drops |
| `zenoh-jni/src/sample_callback.rs` | `SetJniSampleCallback` trait + `HasSampleCallbackSetter` impls |
| `zenoh-jni/src/ext/mod.rs` | Module declarations for ext submodules |
| `zenoh-jni/src/ext/advanced_publisher.rs` | JNI exports for `JNIAdvancedPublisher` |
| `zenoh-jni/src/ext/advanced_subscriber.rs` | JNI exports for `JNIAdvancedSubscriber` |
| `zenoh-jni/src/ext/matching_listener.rs` | `Java_io_zenoh_jni_JNIMatchingListener_freePtrViaJNI` |
| `zenoh-jni/src/ext/sample_miss_listener.rs` | `Java_io_zenoh_jni_JNISampleMissListener_freePtrViaJNI` |

### 3. Modified files

**`zenoh-jni/src/lib.rs`**: Added `pub(crate) mod owned_object;`, `pub(crate) mod sample_callback;`, and `#[cfg(feature = "zenoh-ext")] mod ext;`

**`zenoh-jni/src/session.rs`**: 
- Added imports: `PublisherBuilder`, `SubscriberBuilder`, `Callback`, `OwnedObject`, `SetJniSampleCallback`, `jdouble` (cfg-gated), and zenoh-ext advanced types (cfg-gated)
- Added `Java_io_zenoh_jni_JNISession_openSessionViaJNI` (instance-method alias for zenoh-kotlin compatibility)
- Added `prepare_publisher_builder` private helper
- Added `prepare_subscriber_builder` private helper  
- Added `Java_io_zenoh_jni_JNISession_declareAdvancedPublisherViaJNI` (cfg-gated)
- Added `Java_io_zenoh_jni_JNISession_declareAdvancedSubscriberViaJNI` (cfg-gated)

## Verification

`cargo build --manifest-path zenoh-jni/Cargo.toml` succeeded with no errors.

All 16 required JNI symbols verified with `nm -D`:
- `Java_io_zenoh_jni_JNISession_openSessionViaJNI` ✓
- `Java_io_zenoh_jni_JNISession_declareAdvancedPublisherViaJNI` ✓
- `Java_io_zenoh_jni_JNISession_declareAdvancedSubscriberViaJNI` ✓
- `Java_io_zenoh_jni_JNIAdvancedPublisher_declareMatchingListenerViaJNI` ✓
- `Java_io_zenoh_jni_JNIAdvancedPublisher_declareBackgroundMatchingListenerViaJNI` ✓
- `Java_io_zenoh_jni_JNIAdvancedPublisher_getMatchingStatusViaJNI` ✓
- `Java_io_zenoh_jni_JNIAdvancedPublisher_putViaJNI` ✓
- `Java_io_zenoh_jni_JNIAdvancedPublisher_deleteViaJNI` ✓
- `Java_io_zenoh_jni_JNIAdvancedPublisher_freePtrViaJNI` ✓
- `Java_io_zenoh_jni_JNIAdvancedSubscriber_declareDetectPublishersSubscriberViaJNI` ✓
- `Java_io_zenoh_jni_JNIAdvancedSubscriber_declareBackgroundDetectPublishersSubscriberViaJNI` ✓
- `Java_io_zenoh_jni_JNIAdvancedSubscriber_declareSampleMissListenerViaJNI` ✓
- `Java_io_zenoh_jni_JNIAdvancedSubscriber_declareBackgroundSampleMissListenerViaJNI` ✓
- `Java_io_zenoh_jni_JNIAdvancedSubscriber_freePtrViaJNI` ✓
- `Java_io_zenoh_jni_JNIMatchingListener_freePtrViaJNI` ✓
- `Java_io_zenoh_jni_JNISampleMissListener_freePtrViaJNI` ✓

## Approach

All code was copied verbatim from zenoh-kotlin's JNI layer (at the reference path `/data/home/skynet/tasks/base/workspaces/zenoh-kotlin/task-67/zenoh-kotlin/zenoh-jni/src/`) with copyright year updated to 2026. The implementation is purely additive — no existing zenoh-java code was removed or modified beyond adding new imports and module declarations.

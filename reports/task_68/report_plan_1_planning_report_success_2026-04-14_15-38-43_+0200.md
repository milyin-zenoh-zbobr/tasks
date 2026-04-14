# Implementation Plan: Extend zenoh-java JNI for zenoh-kotlin Compatibility (Phase 1)

## Background

The goal is to make zenoh-kotlin use zenoh-java's compiled native library (`libzenoh_jni`) instead of maintaining its own separate Rust/JNI codebase. This plan covers **Phase 1 only**: adding the missing JNI symbols to zenoh-java's native library.

All changes are **additive-only** — zenoh-java's existing Kotlin API and existing native exports remain completely untouched.

## Closest Analog

The existing zenoh-kotlin `zenoh-jni/src/` is the direct source for the code to be added. The ext files and two new modules (`owned_object.rs`, `sample_callback.rs`) are copied verbatim from zenoh-kotlin. The three new session.rs exports follow the same patterns as the existing zenoh-java session.rs exports, with helper functions adopted from zenoh-kotlin.

## Symbols to Add

| Missing JNI Symbol | Source |
|---|---|
| `Java_io_zenoh_jni_JNISession_openSessionViaJNI` | Compat alias for existing companion-object variant |
| `Java_io_zenoh_jni_JNISession_declareAdvancedSubscriberViaJNI` | zenoh-kotlin `session.rs:240` |
| `Java_io_zenoh_jni_JNISession_declareAdvancedPublisherViaJNI` | zenoh-kotlin `session.rs:365` |
| `Java_io_zenoh_jni_JNIAdvancedPublisher_*` (5 methods) | zenoh-kotlin `ext/advanced_publisher.rs` |
| `Java_io_zenoh_jni_JNIAdvancedSubscriber_*` (5 methods) | zenoh-kotlin `ext/advanced_subscriber.rs` |
| `Java_io_zenoh_jni_JNIMatchingListener_freePtrViaJNI` | zenoh-kotlin `ext/matching_listener.rs` |
| `Java_io_zenoh_jni_JNISampleMissListener_freePtrViaJNI` | zenoh-kotlin `ext/sample_miss_listener.rs` |

## Files to Create (New)

### `zenoh-jni/src/owned_object.rs`
Copy verbatim from zenoh-kotlin. Provides `OwnedObject<T>`: a safe Arc accessor that prevents early drops by offloading `mem::forget` from the call site. Used by advanced publisher/subscriber functions.

### `zenoh-jni/src/sample_callback.rs`
Copy verbatim from zenoh-kotlin. Provides `SetJniSampleCallback` trait + `HasSampleCallbackSetter` implementations for `SubscriberBuilder` and `LivelinessSubscriberBuilder`. All dependencies (`get_java_vm`, `get_callback_global_ref`, `load_on_close`, `bytes_to_java_array`, `slice_to_java_string`) already exist in zenoh-java's `utils.rs`. Uses only base `zenoh` crate types — no feature gate needed.

### `zenoh-jni/src/ext/mod.rs`
Copy verbatim from zenoh-kotlin. Declares submodules: `advanced_publisher`, `advanced_subscriber`, `matching_listener`, `sample_miss_listener`.

### `zenoh-jni/src/ext/advanced_publisher.rs`
Copy verbatim from zenoh-kotlin. Contains 5 JNI exports: `declareMatchingListenerViaJNI`, `declareBackgroundMatchingListenerViaJNI`, `getMatchingStatusViaJNI`, `putViaJNI`, `deleteViaJNI`, `freePtrViaJNI` for `JNIAdvancedPublisher`. All gated with `#[cfg(feature = "zenoh-ext")]` where appropriate.

### `zenoh-jni/src/ext/advanced_subscriber.rs`
Copy verbatim from zenoh-kotlin. Contains 5 JNI exports: `declareDetectPublishersSubscriberViaJNI`, `declareBackgroundDetectPublishersSubscriberViaJNI`, `declareSampleMissListenerViaJNI`, `declareBackgroundSampleMissListenerViaJNI`, `freePtrViaJNI` for `JNIAdvancedSubscriber`.

### `zenoh-jni/src/ext/matching_listener.rs`
Copy verbatim from zenoh-kotlin. Contains 1 JNI export: `Java_io_zenoh_jni_JNIMatchingListener_freePtrViaJNI`.

### `zenoh-jni/src/ext/sample_miss_listener.rs`
Copy verbatim from zenoh-kotlin. Contains 1 JNI export: `Java_io_zenoh_jni_JNISampleMissListener_freePtrViaJNI`.

## Files to Modify

### `zenoh-jni/src/lib.rs`
Add three new module declarations:
- `mod owned_object;` — unconditional (no zenoh-ext dependency)
- `mod sample_callback;` — unconditional (uses only base zenoh types)
- `#[cfg(feature = "zenoh-ext")] mod ext;` — feature-gated, same convention as `zbytes`

### `zenoh-jni/src/session.rs`
This is the most important modification. Add:

**1. New imports** (conditionally gated where needed):
- `jdouble` (under `#[cfg(feature = "zenoh-ext")]`)
- `crate::owned_object::OwnedObject`
- `crate::sample_callback::SetJniSampleCallback`
- Under `#[cfg(feature = "zenoh-ext")]`: `AdvancedPublisher`, `AdvancedPublisherBuilderExt`, `AdvancedSubscriber`, `AdvancedSubscriberBuilderExt`, `CacheConfig`, `HistoryConfig`, `MissDetectionConfig`, `RecoveryConfig`, `RepliesConfig` from `zenoh_ext`

**2. New private helper functions** (copied from zenoh-kotlin `session.rs`):
- `prepare_publisher_builder`: encapsulates key_expr decoding, decode_congestion_control, decode_priority, decode_reliability, and session.declare_publisher chain. Used by `declareAdvancedPublisherViaJNI`.
- `prepare_subscriber_builder`: encapsulates key_expr decoding and session.declare_subscriber with JNI sample callback. Used by `declareAdvancedSubscriberViaJNI`.

**3. New JNI export: `Java_io_zenoh_jni_JNISession_openSessionViaJNI`**
Compat alias: instance-method variant (zenoh-kotlin uses `JNISession` instance method while zenoh-java has `JNISession$Companion` static method). Implementation is identical to the existing companion-object variant — calls the same `open_session(config_ptr)` helper. No zenoh-ext feature gate needed.

**4. New JNI export: `Java_io_zenoh_jni_JNISession_declareAdvancedSubscriberViaJNI`**
Copied from zenoh-kotlin session.rs lines 240–364. Gated with `#[cfg(feature = "zenoh-ext")]`. Takes `HistoryConfig` and `RecoveryConfig` parameters, builds an `AdvancedSubscriber` using `prepare_subscriber_builder(...).advanced()`. Uses `Arc::from_raw` + `mem::forget` pattern consistent with zenoh-java's existing session functions.

**5. New JNI export: `Java_io_zenoh_jni_JNISession_declareAdvancedPublisherViaJNI`**
Copied from zenoh-kotlin session.rs lines 365–490. Gated with `#[cfg(feature = "zenoh-ext")]`. Takes `CacheConfig` and `MissDetectionConfig` parameters, builds an `AdvancedPublisher` using `prepare_publisher_builder(...).advanced()`. Uses `OwnedObject::from_raw` pattern (as in zenoh-kotlin) since that's what the helper function returns.

## Key Design Decisions

1. **No Cargo.toml changes**: zenoh-java already has `default = ["zenoh/default", "zenoh-ext"]` so all new ext code is compiled by default.
2. **Verbatim copy**: `owned_object.rs`, `sample_callback.rs`, and all `ext/` files are copied verbatim from zenoh-kotlin — no adaptation needed since dependency function names and signatures match.
3. **Additive only**: No existing zenoh-java code is modified except `lib.rs` (adding module declarations) and `session.rs` (adding new exports + helpers). Existing functions, their implementations, and the Kotlin API surface are completely untouched.
4. **Feature gates**: `mod ext` in lib.rs follows the same `#[cfg(feature = "zenoh-ext")]` convention as `mod zbytes`. The new functions in session.rs are gated with `#[cfg(feature = "zenoh-ext")]` matching zenoh-kotlin's convention.
5. **Session ownership pattern**: The new `declareAdvancedSubscriberViaJNI` uses `Arc::from_raw` + `mem::forget` (zenoh-java's existing pattern), while `declareAdvancedPublisherViaJNI` uses `OwnedObject` (zenoh-kotlin's pattern). Both are valid; `OwnedObject` is cleaner for the advanced publisher which also uses `prepare_publisher_builder`.

## Verification Steps

After implementation:
1. `cargo build --manifest-path zenoh-jni/Cargo.toml` must succeed with no new warnings
2. `nm -D target/*/libzenoh_jni.so | grep Java_io_zenoh_jni_JNISession_openSessionViaJNI` — should show the instance-method symbol
3. `nm -D target/*/libzenoh_jni.so | grep Advanced` — should show all advanced publisher/subscriber symbols
4. `nm -D target/*/libzenoh_jni.so | grep JNIMatchingListener` and `JNISampleMissListener` — should show freePtrViaJNI symbols

## Implementation Order

1. Create `owned_object.rs` and `sample_callback.rs`
2. Create `ext/` directory with all 5 files
3. Update `lib.rs` with module declarations
4. Update `session.rs` with new imports, helpers, and three new exports
5. Build and verify
## Verdict
The revised Phase 1 plan is **sound and ready for implementation**.

## What I verified

### 1. The previous blocker is genuinely fixed
The earlier adversarial concern was real: local `zenoh-jni/Cargo.toml` currently enables `zenoh-ext` with only `features = ["internal"]`, while upstream `zenoh-kotlin` enables `features = ["unstable", "internal"]`.

The revised plan explicitly adds `unstable`, which is necessary because the advanced pub/sub types used by the copied JNI code come from `zenoh-ext`'s unstable surface.

### 2. The local JNI export gap matches the revised plan exactly
I compared the current local `zenoh-jni/src/**/*.rs` JNI exports against the upstream `eclipse-zenoh/zenoh-kotlin` `zenoh-jni/src/**/*.rs` export surface.

Result: local is missing exactly these 16 upstream symbols:
- `Java_io_zenoh_jni_JNISession_openSessionViaJNI`
- `Java_io_zenoh_jni_JNISession_declareAdvancedSubscriberViaJNI`
- `Java_io_zenoh_jni_JNISession_declareAdvancedPublisherViaJNI`
- `Java_io_zenoh_jni_JNIAdvancedPublisher_declareMatchingListenerViaJNI`
- `Java_io_zenoh_jni_JNIAdvancedPublisher_declareBackgroundMatchingListenerViaJNI`
- `Java_io_zenoh_jni_JNIAdvancedPublisher_getMatchingStatusViaJNI`
- `Java_io_zenoh_jni_JNIAdvancedPublisher_putViaJNI`
- `Java_io_zenoh_jni_JNIAdvancedPublisher_deleteViaJNI`
- `Java_io_zenoh_jni_JNIAdvancedPublisher_freePtrViaJNI`
- `Java_io_zenoh_jni_JNIAdvancedSubscriber_declareDetectPublishersSubscriberViaJNI`
- `Java_io_zenoh_jni_JNIAdvancedSubscriber_declareBackgroundDetectPublishersSubscriberViaJNI`
- `Java_io_zenoh_jni_JNIAdvancedSubscriber_declareSampleMissListenerViaJNI`
- `Java_io_zenoh_jni_JNIAdvancedSubscriber_declareBackgroundSampleMissListenerViaJNI`
- `Java_io_zenoh_jni_JNIAdvancedSubscriber_freePtrViaJNI`
- `Java_io_zenoh_jni_JNIMatchingListener_freePtrViaJNI`
- `Java_io_zenoh_jni_JNISampleMissListener_freePtrViaJNI`

That is exactly the surface the revised plan proposes to add. I did not find extra missing non-advanced JNI exports outside this set.

### 3. The local crate already has the helper surface the copied files depend on
The revised plan’s “verbatim copy” claim is supported by the current repo:
- `get_java_vm`
- `get_callback_global_ref`
- `load_on_close`
- `bytes_to_java_array`
- `slice_to_java_string`
- `decode_congestion_control`
- `decode_priority`
- `decode_reliability`

all exist in local `zenoh-jni/src/utils.rs`, and local `session.rs`/`liveliness.rs` already use the same callback and JNI threading patterns those upstream files rely on.

### 4. The `openSessionViaJNI` alias is a real compatibility gap
Local `session.rs` exports only:
- `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI`

Local Kotlin `JNISession.kt` likewise declares `openSessionViaJNI` only inside the companion object. There is no instance-method JNI export today.

So the revised plan’s additive alias for `Java_io_zenoh_jni_JNISession_openSessionViaJNI` is a legitimate compatibility step for zenoh-kotlin’s expected native symbol and is safe because it can delegate to the same `open_session(config_ptr)` helper.

## Why the approach is appropriate
- The plan stays focused on the JNI layer, which matches the task scope: expose the native ABI needed by zenoh-kotlin without implementing missing higher-level Java APIs.
- The implementation strategy is low-risk because it uses the existing zenoh-kotlin JNI crate as the direct analog rather than inventing a new compatibility layer.
- The module additions (`owned_object`, `sample_callback`, `ext`) and the session additions are consistent with current zenoh-java crate structure and helper conventions.
- Feature-gating `ext` and the advanced session exports on `zenoh-ext` is the correct shape for this crate.

## Non-blocking observations
1. The worker should merge imports/helpers into local `session.rs` rather than replace large sections wholesale, since zenoh-java already has some imports and query-related items not identical to upstream.
2. The plan’s `lib.rs` visibility wording (`pub(crate) mod ...`) is acceptable, but not architecturally important; the key requirement is that the new modules be accessible from sibling modules in the crate.
3. Symbol-level verification with `nm` is the right validation for this phase because the current repo does not yet contain local Kotlin wrapper classes for the advanced JNI types.

## Bottom line
The revised plan fixes the only fundamental issue from the prior version and now cleanly matches both:
- the actual upstream zenoh-kotlin JNI dependency surface, and
- the current zenoh-java crate’s structure and helper conventions.

It is ready for implementation.
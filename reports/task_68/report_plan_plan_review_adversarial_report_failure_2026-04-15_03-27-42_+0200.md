The revised architecture is mostly in the right direction: extracting a primitive-only `zenoh-jni-runtime`, keeping `JNIZBytes` and logger glue in `zenoh-java`, preserving remote/android native packaging, and explicitly handling the scouting companion symbol all match the repository state.

However, the plan is still not implementation-ready because the new advanced Kotlin adapter layer does not match the Rust JNI exports that already exist on this branch.

## Blocking issue 1: planned `JNIAdvancedPublisher` / `JNIAdvancedSubscriber` method shapes do not match the Rust exports

The plan describes `JNIAdvancedPublisher` and `JNIAdvancedSubscriber` as instance classes with methods like:
- `external fun putViaJNI(...)`
- `external fun deleteViaJNI(...)`
- `external fun declareMatchingListenerViaJNI(...)`
- `external fun getMatchingStatusViaJNI()`
- `external fun freePtrViaJNI()`

That is not how the Rust layer is exported.

The Rust functions are all **class/static-style JNI exports with an explicit pointer argument**, for example:
- `Java_io_zenoh_jni_JNIAdvancedPublisher_putViaJNI(..., publisher_ptr: *const AdvancedPublisher)` in `zenoh-jni/src/ext/advanced_publisher.rs`
- `Java_io_zenoh_jni_JNIAdvancedPublisher_deleteViaJNI(..., publisher_ptr: *const AdvancedPublisher)` in `zenoh-jni/src/ext/advanced_publisher.rs`
- `Java_io_zenoh_jni_JNIAdvancedPublisher_declareMatchingListenerViaJNI(..., advanced_publisher_ptr: *const AdvancedPublisher, callback, on_close)` in `zenoh-jni/src/ext/advanced_publisher.rs`
- `Java_io_zenoh_jni_JNIAdvancedPublisher_getMatchingStatusViaJNI(..., advanced_publisher_ptr: *const AdvancedPublisher)` in `zenoh-jni/src/ext/advanced_publisher.rs`
- `Java_io_zenoh_jni_JNIAdvancedPublisher_freePtrViaJNI(..., publisher_ptr: *const AdvancedPublisher)` in `zenoh-jni/src/ext/advanced_publisher.rs`
- `Java_io_zenoh_jni_JNIAdvancedSubscriber_*` functions in `zenoh-jni/src/ext/advanced_subscriber.rs` follow the same pattern.

If a worker follows the plan literally and declares these as true instance JNI methods without an explicit `Long ptr` parameter, Kotlin will generate different JNI call shapes than Rust exports. That will lead to binding failures / `UnsatisfiedLinkError` rather than a working wrapper.

### Required revision
The plan should explicitly say that the advanced Kotlin wrappers must follow the **same pattern as current wrappers like `JNIPublisher`, `JNISubscriber`, and `JNIQueryable`**:
1. Store `ptr: Long` in the wrapper instance.
2. Expose normal Kotlin methods such as `put(...)`, `delete(...)`, `declareMatchingListener(...)`, etc.
3. Have those Kotlin methods call **private external functions that still take the pointer as an explicit parameter** (or equivalent companion-object static externals).
4. Keep `freePtrViaJNI(ptr: Long)` in a static/companion-style shape, not as a no-arg true instance native method.

Without that correction, the core new runtime bindings will be wired to the wrong JNI ABI.

## Blocking issue 2: `declareDetectPublishersSubscriberViaJNI` is missing a required `history` parameter in the plan

The plan’s proposed `JNIAdvancedSubscriber` API lists:
- `declareDetectPublishersSubscriberViaJNI(callback: JNISubscriberCallback, onClose: JNIOnCloseCallback): Long`
- `declareBackgroundDetectPublishersSubscriberViaJNI(callback: JNISubscriberCallback, onClose: JNIOnCloseCallback)`

But the Rust exports require an additional boolean before the callback:
- `Java_io_zenoh_jni_JNIAdvancedSubscriber_declareDetectPublishersSubscriberViaJNI(..., history: jboolean, callback, on_close)` in `zenoh-jni/src/ext/advanced_subscriber.rs`
- `Java_io_zenoh_jni_JNIAdvancedSubscriber_declareBackgroundDetectPublishersSubscriberViaJNI(..., history: jboolean, callback, on_close)` in the same file.

So the plan currently underspecifies the Kotlin runtime surface for detect-publishers subscriptions. A worker following it would implement the wrong function signature and either fail to bind or silently lose the history option.

### Required revision
The plan should explicitly include the `history` boolean in both detect-publishers methods and carry that option through whatever zenoh-java / zenoh-kotlin facade will expose it.

## Non-blocking observations
- The revised plan’s fixes for `Logger.start()` loading, `JNIZBytes` staying in `zenoh-java`, remote/android packaging preservation, and keeping scouting companion-bound are all good and should stay.
- The overall extraction direction remains sound once the advanced JNI adapter signatures are corrected.

## Recommendation
Revise the plan before implementation so that:
1. All advanced Kotlin JNI adapters mirror the **existing static-export + explicit pointer parameter** convention already used by the Rust exports.
2. Detect-publishers subscriber methods include the required `history` argument.
3. Any close/free methods for advanced wrappers also preserve the existing static JNI shape rather than switching to no-arg native instance methods.

After those corrections, the plan would be ready for implementation.
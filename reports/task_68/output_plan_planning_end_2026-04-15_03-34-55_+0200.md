The plan has been submitted. Here's a summary of what was designed and the key decisions:

## Plan Summary

**Goal**: Create a `zenoh-jni-runtime` Gradle subproject containing primitive-only JNI adapters that both `zenoh-java` and `zenoh-kotlin` can depend on.

**Key design decisions addressing all previous blocking issues:**

1. **Correct JNI binding pattern** (fixes ctx_rec_4 blocking issue #1): All advanced adapter classes (`JNIAdvancedPublisher`, `JNIAdvancedSubscriber`, `JNIMatchingListener`, `JNISampleMissListener`) follow the **`JNIPublisher` pattern** — store `val ptr: Long`, declare `private external fun` with explicit ptr parameter matching Rust's static JNI export shape, public wrapper methods call private externals.

2. **`history` parameter included** (fixes ctx_rec_4 blocking issue #2): `declareDetectPublishersSubscriberViaJNI` and its background variant both include `history: Boolean` as required by the Rust exports.

3. **`JNIZBytes` stays in zenoh-java** — returns `ZBytes` facade type, cannot be primitive-only.

4. **`JNIScout` preserves Companion prefix** — companion object without `@JvmStatic` on `scoutViaJNI` preserves `_00024Companion_` JNI symbol.

5. **Logger loading race resolved** — `Logger.start()` explicitly references `ZenohLoad` before calling `startLogsViaJNI`.

6. **Full build pipeline preserved** — `zenoh-jni-runtime/build.gradle.kts` copies local + remote + Android native packaging from `zenoh-java/build.gradle.kts`.
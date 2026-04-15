The plan is complete. Here's a summary of what was designed:

## Plan Summary

**Goal**: Create a `zenoh-jni-runtime` Gradle subproject containing primitive-only JNI adapters that both zenoh-java and (future) zenoh-kotlin can depend on.

**Key design decisions addressing the adversarial review:**

1. **JNIZBytes stays in zenoh-java** — it returns `ZBytes` (a facade type), zenoh-kotlin doesn't need it
2. **Logger.start() safety** — `Logger.start()` explicitly references the runtime's `ZenohLoad` before calling `startLogsViaJNI`, guaranteeing the library is loaded
3. **Scouting JNI symbol preserved** — `JNIScout.companion` does NOT add `@JvmStatic` to `scoutViaJNI`, preserving the `_00024Companion_` symbol matching the existing Rust export
4. **Full native packaging** — `zenoh-jni-runtime/build.gradle.kts` replicates all three packaging modes from zenoh-java: local build, remote publication (`../jni-libs`), and Android cargo integration

**New additions for advanced pub/sub**: `JNIAdvancedPublisher`, `JNIAdvancedSubscriber`, `JNIMatchingListener`, `JNISampleMissListener`, and two new callback interfaces matching the Rust JNI signatures already on the branch.
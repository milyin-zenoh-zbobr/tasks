The plan is complete. Here's a summary of key corrections from the previous planning iterations:

**What previous reviews got wrong (verified by reading actual files):**
- `JNIConfig` factory methods DO return `Long` (not `JNIConfig` objects directly)
- `JNISession.open()` takes `configPtr: Long` (not a `JNIConfig` object)
- `JNIZBytes.kt` is NOT in `zenoh-jni-runtime` — it's only in the zenoh-java facade — so zenoh-kotlin must keep its own copy
- `JNILiveliness` IS a separate `public object` in zenoh-jni-runtime (not merged into JNISession)

**What the plan adds that was missing:**
- Conditional `includeBuild` (skipped when `remotePublication=true`) solves the publication story without double-publishing
- `examples/build.gradle.kts`, `publish-android.yml`, and `ZError.kt` deletion are all explicitly covered
- `Logger.kt` stays unchanged (its `external fun startLogsViaJNI` resolves to zenoh-java's Rust crate)
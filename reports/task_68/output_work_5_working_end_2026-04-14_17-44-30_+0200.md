The task is complete. Here's what was done:

**Changes made (commit `eba165a`):**

1. **`zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`** — Added `@JvmStatic` to `openSessionViaJNI` in the companion object. This causes Kotlin to emit the JNI symbol `Java_io_zenoh_jni_JNISession_openSessionViaJNI` (outer-class form) instead of the `$Companion`-suffixed variant.

2. **`zenoh-jni/src/session.rs`** — Removed the redundant `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI` function (~30 lines). Updated the doc comment on the surviving function to describe it as the canonical shared binding rather than "instance-method variant for zenoh-kotlin compatibility".

**Result:** zenoh-java and zenoh-kotlin now share a single `openSessionViaJNI` JNI symbol with no Rust duplication. The Rust crate builds cleanly.
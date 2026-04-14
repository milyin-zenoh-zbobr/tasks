The plan is ready. Here's the summary:

## Plan: Add `@JvmStatic` to align JNI symbol name

The previous plan was rejected because it proposed moving `openSessionViaJNI` to instance scope + creating a dummy `JNISession(0L)`, which distorts the class model.

**Better approach** (identified by the review): use `@JvmStatic` on the `external fun`, following the existing pattern in `JNIZBytes.kt`. Two-file change:

1. **`JNISession.kt`** — Add `@JvmStatic` to `private external fun openSessionViaJNI(configPtr: Long): Long` in the companion object. This makes Kotlin emit the native binding on the outer `JNISession` class (generating `Java_io_zenoh_jni_JNISession_openSessionViaJNI`). The factory `open()` function and call sites stay identical.

2. **`session.rs`** — Remove `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI` (lines ~51–77). The instance variant at line ~1227 remains as the sole implementation.

This is the minimal, semantically clean change: 1 annotation added, 1 Rust function removed.
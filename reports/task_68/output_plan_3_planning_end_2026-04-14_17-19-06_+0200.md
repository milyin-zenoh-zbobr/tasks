The plan is complete. Here's a summary of what I found and what needs to be done:

## Analysis

After exploring both zenoh-java and zenoh-kotlin codebases, I found that **only one JNI function has a naming difference** between the two:

- **zenoh-java** exports: `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI` (companion object style)
- **zenoh-kotlin** expects: `Java_io_zenoh_jni_JNISession_openSessionViaJNI` (instance method style)

All other 60+ JNI functions already have identical names. Task 67 added the kotlin-style variant as an alias — now both are exported. Task 68 requires consolidating to just one.

## Plan (2 targeted changes)

1. **`zenoh-jni/src/session.rs`** — Remove the companion-object variant (`Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI`, lines ~61–77)

2. **`zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`** — Move `private external fun openSessionViaJNI(...)` from the `companion object` to the class body (instance level), and update the companion's `open()` factory to create a temporary `JNISession(0L)` instance to call it. This makes zenoh-java emit the kotlin-compatible JNI symbol name.
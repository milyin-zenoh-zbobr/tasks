I reviewed the revised plan against the checked-out codebase and it is ready for implementation.

Why the plan is sound:
- `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt` currently keeps `openSessionViaJNI` inside `companion object`, and `open(config)` is a factory that returns a fully initialized `JNISession(sessionPtr)`. The revised plan preserves that model instead of introducing a dummy `JNISession(0L)` instance.
- The duplication hotspot is real: `zenoh-jni/src/session.rs` currently exports both `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI` and `Java_io_zenoh_jni_JNISession_openSessionViaJNI`, with identical behavior through `open_session(config_ptr)`.
- The repo already uses the relevant Kotlin/JVM pattern for JNI naming: `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNIZBytes.kt` declares `@JvmStatic external fun ...` on an object, which is exactly the evidence needed that the outer-class JNI symbol form is the intended pattern here.
- The repo also broadly uses `@JvmStatic` in companion objects (for example in `zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt`), so the direction is stylistically consistent.

Implementation guidance I consider correct:
1. Add `@JvmStatic` to `openSessionViaJNI` in `JNISession`’s companion object.
2. Keep `open(config)` unchanged.
3. Remove `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI` from `zenoh-jni/src/session.rs` once the Kotlin side is bound to the outer-class symbol.

Non-blocking observations:
- The surviving Rust comment around `Java_io_zenoh_jni_JNISession_openSessionViaJNI` currently describes it as an "instance-method variant for zenoh-kotlin compatibility". After this change it becomes the canonical shared binding, so that comment should be updated for clarity while the worker is in that file.
- For verification, the repo’s documented/CI JVM task is `gradle jvmTest`, and `zenoh-java/build.gradle.kts` wires `compileKotlinJvm` to `buildZenohJni`. So the worker should prefer the repo’s actual Gradle entrypoints rather than relying on a wrapper-specific command.

Conclusion: no architectural blockers remain; the plan is sound and implementation-ready.
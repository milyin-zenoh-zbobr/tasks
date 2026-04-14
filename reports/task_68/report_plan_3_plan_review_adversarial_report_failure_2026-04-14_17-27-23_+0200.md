The plan correctly identifies the actual duplication hotspot: in this repo, `zenoh-jni/src/session.rs` exports both `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI` and `Java_io_zenoh_jni_JNISession_openSessionViaJNI`, while `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt` still declares `openSessionViaJNI` inside the companion object. So the intended end state — one `Java_io_zenoh_jni_JNISession_openSessionViaJNI` symbol shared with zenoh-kotlin — is sound.

However, the proposed implementation direction is weaker than it needs to be, and I do not think it is ready for execution as written.

1. **It changes zenoh-java’s adapter model in a way that does not match the class design.**
   - `zenoh-java` models `JNISession` as `internal class JNISession(val sessionPtr: Long)` and exposes a factory-style `open(config): JNISession` that returns a fully initialized wrapper.
   - `zenoh-kotlin` uses a different shape: its `JNISession` has mutable state and an instance `open(config)` that initializes `sessionPtr` later.
   - The plan tries to imitate the kotlin JNI naming by moving only the native declaration to instance scope and then creating a fake `JNISession(0L)` just to call it. That introduces an invalid placeholder session object into a class that is otherwise designed to always wrap a real pointer.
   - Even if it works today because the native side ignores the receiver, this is an unnecessary semantic distortion in the Java binding.

2. **There is an existing codebase pattern that may avoid the dummy-instance hack entirely, and the plan should evaluate that first.**
   - This repo already uses `@JvmStatic` in common code, and `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNIZBytes.kt` is especially relevant: its `@JvmStatic external` methods map to unmangled Rust symbols like `Java_io_zenoh_jni_JNIZBytes_serializeViaJNI` / `deserializeViaJNI` with no `00024Companion` suffix.
   - That means the planner has not ruled out a cleaner path that preserves the existing `JNISession.open(config): JNISession` factory shape while still binding to `Java_io_zenoh_jni_JNISession_openSessionViaJNI`.
   - At minimum, the plan should be revised to explicitly prefer the static-bridge approach if it works, and only fall back to the instance-method rewrite if it is proven not to.

3. **The verification step is not aligned with this repository as checked out.**
   - The repo snapshot does not include a Gradle wrapper, so `./gradlew build` is not an accurate concrete verification command here.
   - The revised plan should reference the actual existing build entrypoint/tasks for this repo rather than a wrapper command that is not present.

**Recommendation for plan revision**

Keep the end goal, but change the implementation guidance:
- remove the companion-only Rust export once the Kotlin side is definitely bound to `Java_io_zenoh_jni_JNISession_openSessionViaJNI`;
- first try to preserve the current zenoh-java factory/open pattern and generate the outer-class JNI name using the same JVM-static style already used elsewhere in the repo;
- only if that is not viable should the plan fall back to moving `openSessionViaJNI` to instance scope, and if it does, that fallback should be called out as a compromise rather than the preferred design.

With that revision, the plan would be ready to implement.
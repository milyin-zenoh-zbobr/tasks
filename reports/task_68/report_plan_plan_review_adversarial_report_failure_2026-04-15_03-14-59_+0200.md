The overall idea — extracting a reusable JNI runtime module and moving facade-object assembly back into `zenoh-java` — is sound. However, the current plan is not ready for implementation because several of its core assumptions do not match the repository state.

1. The plan says some adapters can be moved "as-is" because they are already primitive-only, but that is not true.
   - `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNIPublisher.kt` still depends on facade-layer types `Encoding` and `IntoZBytes` and performs conversion logic in the adapter itself.
   - `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNIZBytes.kt` depends on `ZBytes`, and `zenoh-java/src/commonMain/kotlin/io/zenoh/ext/ZSerializer.kt` / `ZDeserializer.kt` call it directly.
   This directly conflicts with the stated runtime constraint of "zero references to io.zenoh.* facade types". A worker following the plan would under-scope the refactor. The plan must either explicitly refactor these adapters too, or leave zenoh-java-only helpers such as `JNIZBytes` in `zenoh-java` instead of the shared runtime.

2. Removing all explicit `ZenohLoad` usage from `zenoh-java` would break the logging path.
   - `zenoh-java/src/commonMain/kotlin/io/zenoh/Zenoh.kt` currently touches `ZenohLoad` before calling `Logger.start(...)`.
   - `zenoh-java/src/commonMain/kotlin/io/zenoh/Logger.kt` exposes `startLogsViaJNI` as an external method on the facade-side `Logger` class.
   If loading is only triggered when a runtime JNI adapter is first used, `Logger.start()` can execute before any runtime class is initialized and hit an `UnsatisfiedLinkError`. The plan needs an explicit replacement for this load guarantee: either keep a callable load hook in zenoh-java, or make `Logger.start()` itself force runtime loading.

3. One of the JNI symbol assumptions in the plan is stale.
   - The Rust scouting export is still `Java_io_zenoh_jni_JNIScout_00024Companion_scoutViaJNI` (and the matching free function), in `zenoh-jni/src/scouting.rs`.
   The plan only mentions the `openSessionViaJNI` normalization and reads as if the companion-prefix issue is already generally resolved. That is not true for scouting. This does not make extraction impossible, but the worker must be told either to preserve the existing companion-based Kotlin binding for scouting or to update the Rust symbol as part of the work.

4. The build/publishing plan is incomplete for the artifact that will actually be consumed by `zenoh-kotlin`.
   - `zenoh-java/build.gradle.kts` currently has distinct handling for local packaging (`../zenoh-jni/target/$buildMode`) and remote publication (`../jni-libs`), plus Android cargo integration hooks.
   - Step 1b only describes packaging raw libraries from `../zenoh-jni/target/`.
   If `zenoh-jni-runtime` becomes the published dependency carrying the native binaries, the new module must explicitly preserve the existing remote-publication and Android packaging behavior. Otherwise the published runtime can be missing the native libraries even if local builds work.

Recommended revision:
1. Narrow the shared module to the JNI surface actually needed by `zenoh-kotlin`, instead of assuming every current `io.zenoh.jni.*` file belongs there.
2. Explicitly classify adapters into:
   - shared primitive runtime,
   - zenoh-java-only facade glue (`JNIZBytes`, possibly logger load glue, and any adapter still tied to `Encoding`/`ZBytes`/`IntoZBytes` until refactored).
3. Add a concrete loading strategy for `Logger.start()` before removing `ZenohLoad` references from `zenoh-java`.
4. State that `zenoh-jni-runtime` must preserve both local and remote native packaging behavior, not just local `target/` resources.
5. Clarify scouting: keep the current companion-bound JNI shape or update the Rust export and Kotlin declaration together.

With those corrections, the architecture would be implementable and much less likely to send the worker into avoidable breakage.
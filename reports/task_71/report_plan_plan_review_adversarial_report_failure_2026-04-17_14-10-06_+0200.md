The plan has the correct high-level direction: consume `zenoh-jni-runtime` from the zenoh-java PR, delete zenoh-kotlin’s duplicated JNI wrapper layer, and remove the local `zenoh-jni` Rust crate. I checked the codebase and the referenced PR surface, and the runtime API assumptions are broadly valid: `zenoh-jni-runtime` really exports thin primitive JNI adapters such as `JNIConfig.loadDefault/loadFromFile/loadFromJson/loadFromYaml`, `JNISession.open(...)`, `JNIScout.scout(...)`, `JNILogger.startLogs(...)`, plus public `ZenohLoad`, `Target`, callback interfaces, and `io.zenoh.exceptions.ZError`.

However, the plan has several significant issues that should be fixed before implementation:

1. **The proposed Gradle task wiring for the included build is wrong.**
   The plan says to add `tasks.named("compileKotlinJvm") { dependsOn(":zenoh-jni-runtime:buildZenohJni") }` from `zenoh-kotlin/build.gradle.kts`. After switching to `includeBuild("zenoh-java")`, `zenoh-jni-runtime` is part of an **included build**, not a regular subproject of the current build. A plain project-path dependency like `":zenoh-jni-runtime:buildZenohJni"` will not work as written. This is a fundamental build-architecture mistake. The implementation should either rely on dependency substitution/building of the included runtime, or explicitly reference the included build task via Gradle’s included-build API.

2. **The plan misses `examples/build.gradle.kts`, which still hard-depends on the local Rust crate being deleted.**
   The examples build currently does both of the following:
   - runs `cargo build --release --manifest-path ../zenoh-jni/Cargo.toml`
   - sets `-Djava.library.path=../zenoh-jni/target/release`
   If the worker follows the plan and deletes `zenoh-jni/`, example runs will immediately break. This file must be part of the migration plan.

3. **The plan updates CI and `publish-jvm.yml`, but misses `publish-android.yml`.**
   Android publication is part of the repo’s release flow and currently checks out the repository directly. Once zenoh-java becomes a submodule/composite build input, Android publishing also needs submodule initialization and any corresponding build-path adjustments. As written, the plan would leave Android publication inconsistent with the new repository layout.

4. **The plan should be more explicit about duplicate class removal, especially `ZError`.**
   The runtime actually ships `io.zenoh.exceptions.ZError`, `io.zenoh.ZenohLoad`, and `io.zenoh.Target`. `ZenohLoad`/`Target` are already called out, but `ZError` is left as a “verify/consolidate” note. That is too soft: keeping the local `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt` alongside the runtime dependency creates a duplicate-type conflict risk and should be treated as an explicit removal/consolidation step.

5. **Be careful not to re-embed the native runtime into zenoh-kotlin unnecessarily.**
   The plan says to point zenoh-kotlin resource directories at `../zenoh-java/zenoh-jni/target/$buildMode` for local builds. That may work, but it weakens the architectural goal: `zenoh-jni-runtime` already owns the native packaging/build logic. The preferred plan should make zenoh-kotlin depend on the runtime module, and only add extra path/task wiring where there is a proven test/runtime need. Otherwise the migration still leaves zenoh-kotlin partially coupled to zenoh-java’s Rust output layout.

## Recommended revision

Keep the overall migration strategy, but revise the plan so it explicitly covers:
- correct composite-build task/dependency handling for `includeBuild("zenoh-java")`
- `examples/build.gradle.kts`
- `publish-android.yml` in addition to CI and `publish-jvm.yml`
- explicit removal/consolidation of local `ZError`
- minimizing direct resource/path coupling to `zenoh-java/zenoh-jni/target` unless strictly necessary

With those fixes, the plan should be sound.
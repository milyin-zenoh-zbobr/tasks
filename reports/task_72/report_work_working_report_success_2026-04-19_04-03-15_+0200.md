# Task Complete: zenoh-kotlin depends on zenoh-jni-runtime

## Summary
All phases of the plan have been implemented and verified. 113 JVM tests pass.

## Work Done

### Phase 0: Add zenoh-java as git submodule (prior session)
- Added `zenoh-java` as submodule pointing to `eclipse-zenoh/zenoh-java` on the `common-jni` branch
- Settings.gradle.kts: `includeBuild("zenoh-java")` with dependency substitution

### Phase 1: Update Gradle build configuration (prior session)
- zenoh-kotlin/build.gradle.kts: Added `zenoh-jni-runtime` dependency, defined `jvmAndAndroidMain` source set

### Phase 2: Move ZSerialize/ZDeserialize to jvmAndAndroidMain (prior session)
- Moved ZSerialize.kt and ZDeserialize.kt to jvmAndAndroidMain per user request (kotlin-reflect not available in Kotlin/Native)

### Phase 3: Delete JNI adapters and adapt domain classes (prior session)
- Deleted all old JNI adapter classes
- Adapted Session.kt, JNILiveliness.kt, and all domain classes to use zenoh-jni-runtime APIs directly

### Phase 4: Remove all Rust code
- Deleted `zenoh-jni/` directory (entire Rust crate)
- Deleted `rust-toolchain.toml`

### Phase 5: Update examples/build.gradle.kts
- Removed `CompileZenohJNI` task, `dependsOn`, and `-Djava.library.path` JVM args

### Phase 6: Update CI workflows
- ci.yml: Added `submodules: recursive`, removed Rust lint/build steps
- publish-jvm.yml: Removed 6-platform cross-compilation matrix, simplified to single publish job
- publish-android.yml: Removed NDK setup, Rust cross-compilation steps

### Bug Fixes (verification phase)
- `Query.kt`: Fixed `ntpValue` property access to `ntpValue()` function call
- `ReplyKeyExpr.kt`: Reordered enum so `MATCHING_QUERY=0, ANY=1` to match Rust's decode mapping
- `Session.undeclare(KeyExpr)`: Fixed double-free SIGABRT by nulling `jniKeyExpr` after undeclare and returning failure if already undeclared

## Commits
- `4986cd63` - chore: remove zenoh-jni Rust crate and rust-toolchain.toml
- `4d8ea8aa` - build: remove CompileZenohJNI task and cargo wiring from examples
- `63114ebc` - ci: remove Rust build steps, simplify workflows to use zenoh-jni-runtime
- `c8b20e92` - fix: correct ntpValue call, ReplyKeyExpr ordinal, and KeyExpr undeclare

## Test Results
All 113 JVM tests pass. BUILD SUCCESSFUL.
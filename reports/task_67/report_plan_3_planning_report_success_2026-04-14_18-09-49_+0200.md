# Plan: Make zenoh-kotlin Based on zenoh-java

## zenoh-java PR Verification

The PR `milyin-zenoh-zbobr/zenoh-java#4` (branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`) was verified against zenoh-kotlin's complete list of JNI symbols.

**All 65 JNI symbols needed by zenoh-kotlin are present in the PR:**

| Category | Status |
|---|---|
| Base symbols (config, key_expr, session, publisher, subscriber, queryable, querier, query, liveliness, scouting, zbytes, zenoh_id) — same companion object patterns match exactly | Already in zenoh-java ✅ |
| `Java_io_zenoh_jni_JNISession_openSessionViaJNI` (instance-method variant) | Added in PR ✅ |
| `Java_io_zenoh_jni_JNISession_declareAdvancedPublisherViaJNI` | Added in PR ✅ |
| `Java_io_zenoh_jni_JNISession_declareAdvancedSubscriberViaJNI` | Added in PR ✅ |
| `JNIAdvancedPublisher` — 6 functions | Added in PR ✅ |
| `JNIAdvancedSubscriber` — 5 functions | Added in PR ✅ |
| `JNIMatchingListener_freePtrViaJNI` | Added in PR ✅ |
| `JNISampleMissListener_freePtrViaJNI` | Added in PR ✅ |

**Nothing is missing.** Note: `JNIConfig.getIdViaJNI` appears in zenoh-kotlin's `JNIConfig.kt` (line 71) but has no Rust implementation in either repo and is never called — dead code, can be ignored.

## Implementation Plan for zenoh-kotlin

### 1. Delete Rust crate
- Delete `zenoh-jni/` directory entirely
- Delete `rust-toolchain.toml`

### 2. `settings.gradle.kts`
Remove `include(":zenoh-jni")`.

### 3. `zenoh-kotlin/build.gradle.kts`

**Remove:**
- `import com.nishtahir.CargoExtension`
- `apply(plugin = "org.mozilla.rust-android-gradle.rust-android")` + `configureCargo()` call
- `buildZenohJni` task, `buildZenohJNI()` helper, `BuildMode` enum
- `tasks.named("compileKotlinJvm") { dependsOn("buildZenohJni") }`
- `tasks.whenObjectAdded { ... cargoBuild ... }` (Android JNI merge trigger)
- `configureCargo()` function definition
- References to `../zenoh-jni/target/$buildMode` in resources + test systemProperty

**Add:**
- Gradle property `zenohJavaDir` (default: `"../zenoh-java"`) pointing to local zenoh-java checkout
- `buildZenohJavaNative` task: runs `cargo build [--release] --manifest-path {zenohJavaDir}/zenoh-jni/Cargo.toml`
- `tasks.named("compileKotlinJvm") { dependsOn("buildZenohJavaNative") }` (non-remote-publication only)
- For Android: update `configureCargo()` to use `{zenohJavaDir}/zenoh-jni` as cargo module

**Update (local build paths):**
- `jvmMain` local resources: `{zenohJavaDir}/zenoh-jni/target/$buildMode`
- `jvmTest` resources: same
- `systemProperty("java.library.path", "{zenohJavaDir}/zenoh-jni/target/$buildMode")`

**Keep unchanged:**
- `isRemotePublication` flag + `jni-libs/` directory path (CI still works the same way)

### 4. `examples/build.gradle.kts`
- Update `CompileZenohJNI` task: build from `{zenohJavaDir}/zenoh-jni/Cargo.toml`
- Update `java.library.path` for runners: `{zenohJavaDir}/zenoh-jni/target/release`

### 5. GitHub Actions workflows

In `publish-jvm.yml` and `publish-android.yml` — after "Checkout source code", add:
```yaml
- name: Checkout zenoh-java
  uses: actions/checkout@v4
  with:
    repository: milyin-zenoh-zbobr/zenoh-java
    ref: zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin
    path: zenoh-java
```
Change all `--manifest-path zenoh-jni/Cargo.toml` → `--manifest-path zenoh-java/zenoh-jni/Cargo.toml`
Change packaging paths: `zenoh-jni/target/${TARGET}/release/` → `zenoh-java/zenoh-jni/target/${TARGET}/release/`

In `ci.yml`: apply same changes if it runs a native build.

### 6. `zenoh-kotlin/src/` — NO CHANGES
All Kotlin source files untouched. Public API unchanged.

## Verification Steps

1. Checkout zenoh-java's PR branch at `../zenoh-java` relative to zenoh-kotlin root
2. `./gradlew :zenoh-kotlin:jvmTest` — all tests pass
3. `./gradlew :examples:ZPub` + `:examples:ZSub` — base pub/sub works
4. `./gradlew :examples:ZAdvancedPublisher` + `:examples:ZAdvancedSubscriber` — ext features work
5. Verify zenoh-kotlin's JAR contains `{target}/{target}.zip` native libs from zenoh-java
6. Verify no `zenoh-jni/` Rust artifacts appear in the build

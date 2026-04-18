# Implementation Plan: Make zenoh-kotlin Depend on zenoh-jni-runtime

## Context

zenoh-kotlin currently bundles its own Rust/JNI native library (`zenoh-jni/` directory) and a set of Kotlin JNI wrapper classes (`io.zenoh.jni.*`). The zenoh-java project's PR #466 extracts this JNI layer into a standalone reusable library called `zenoh-jni-runtime` (Maven: `org.eclipse.zenoh:zenoh-jni-runtime`). This plan replaces zenoh-kotlin's own native library with zenoh-jni-runtime, eliminating all Rust code from the repo.

**Status:** zenoh-java PR #466 is still open (not merged). The submodule must point to its source branch for local development.

**Chosen approach:** Add zenoh-java as a git submodule, use a Gradle composite build for local development, and depend on published `org.eclipse.zenoh:zenoh-jni-runtime` for remote publication. This avoids cross-repo Rust builds in zenoh-kotlin CI while maintaining local buildability.

---

## Phase 0: Verify API Compatibility (Critical First Step)

Before making changes, verify that zenoh-jni-runtime fully covers zenoh-kotlin's JNI surface:

1. Clone the zenoh-jni-runtime source from the PR #466 branch locally.
2. Compare the JNI class list in `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/` with zenoh-kotlin's `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/`.
3. Check whether zenoh-jni-runtime's JNI classes reference zenoh-kotlin types (Session, Config, ZBytes, etc.) or only primitive JNI types — this determines if the classes can be used directly or if an adapter layer is needed.
4. Verify that `JNIZBytes` (in `jvmAndAndroidMain`) in zenoh-jni-runtime has compatible signatures with zenoh-kotlin's usage.
5. Confirm that `ZenohLoad` in zenoh-jni-runtime is in the same `io.zenoh` package and uses the same `internal actual object` pattern, so zenoh-kotlin's own platform-specific ZenohLoad can be deleted.

**If incompatibilities are found**, stop and report — the task states this explicitly.

---

## Phase 1: Add zenoh-java as Git Submodule

**Files to create:**
- `.gitmodules` — add zenoh-java submodule entry

**Steps:**
1. Add zenoh-java as a submodule at path `zenoh-java`, pinned to the PR #466 source branch (or a specific commit SHA from that branch).
2. Commit the submodule entry to the work branch.

```
git submodule add -b <pr-branch> https://github.com/eclipse-zenoh/zenoh-java.git zenoh-java
```

---

## Phase 2: Update Gradle Build to Use zenoh-jni-runtime

### 2a. `settings.gradle.kts` (root)

- Remove `:zenoh-jni` from the included subprojects.
- Add the zenoh-java composite build for local resolution:
  ```kotlin
  includeBuild("zenoh-java") {
      dependencySubstitution {
          substitute(module("org.eclipse.zenoh:zenoh-jni-runtime")).using(project(":zenoh-jni-runtime"))
      }
  }
  ```
  This makes local builds resolve `zenoh-jni-runtime` from the submodule source, while published builds use Maven Central.

### 2b. Root `build.gradle.kts`

- Remove the `org.mozilla.rust-android-gradle` plugin from `buildscript.dependencies` and `plugins {}`.
- Remove `com.android.tools.build:gradle` from buildscript (or keep if still needed for zenoh-kotlin's Android target — verify).

### 2c. `zenoh-kotlin/build.gradle.kts`

**Add dependency on zenoh-jni-runtime:**
```kotlin
val commonMain by getting {
    dependencies {
        api("org.eclipse.zenoh:zenoh-jni-runtime:[version]")
        // existing dependencies...
    }
}
```
The version should match `rootProject.version` or be read from `version.txt`.

**Remove Rust build integration:**
- Delete `buildZenohJni` task registration and the `buildZenohJNI()` function.
- Remove `tasks.named("compileKotlinJvm") { dependsOn("buildZenohJni") }`.
- Remove `BuildMode` enum.
- Remove `isRemotePublication` conditional for `jvmMain` resources (no more `jni-libs` or `zenoh-jni/target` resources).
- Remove the Cargo plugin configuration (`configureCargo()` call and function).
- Remove `configureAndroid()` changes related to NDK — keep Android target config but remove Cargo-specific bits.
- Remove `tasks.whenObjectAdded { ... cargoBuild ... }` block.
- Remove `tasks.withType<Test>` block that sets `java.library.path` to the Rust target.

**Keep:** All publishing configuration, signing, POM metadata — these remain unchanged.

---

## Phase 3: Remove Kotlin JNI Wrapper Classes (now provided by zenoh-jni-runtime)

If Phase 0 confirms that zenoh-jni-runtime provides identical `io.zenoh.jni.*` classes:

**Delete from `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/`:**
- All 16 JNI adapter files: `JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt`, `JNIConfig.kt`, `JNIKeyExpr.kt`, `JNILiveliness.kt`, `JNILivelinessToken.kt`, `JNIMatchingListener.kt`, `JNIPublisher.kt`, `JNIQuerier.kt`, `JNIQueryable.kt`, `JNIQuery.kt`, `JNISampleMissListener.kt`, `JNIScout.kt`, `JNISession.kt`, `JNISubscriber.kt`, `JNIZenohId.kt`
- All 7 callback interfaces in `callbacks/`
- `JNIZBytes.kt` (in jvmAndAndroid or commonMain — wherever it lives)

**Delete platform-specific ZenohLoad (if zenoh-jni-runtime provides its own):**
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (ZenohLoad implementation)
- `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` (ZenohLoad implementation)
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt` (if provided by zenoh-jni-runtime)

> **Note:** If zenoh-jni-runtime's JNI classes reference zenoh-kotlin types (Session, Config, ZBytes, etc.) that create a circular dependency, an alternative design is needed: keep zenoh-kotlin's JNI wrapper classes as thin delegates that forward to zenoh-jni-runtime's primitive-type JNI bindings. Resolve this during Phase 0.

---

## Phase 4: Remove All Rust Code

**Delete entirely:**
- `zenoh-jni/` directory (all Rust source files, `Cargo.toml`, `Cargo.lock`)
- `rust-toolchain.toml` (root level)
- `zenoh-jni/` entry from `settings.gradle.kts` include list (already handled in Phase 2a)

---

## Phase 5: Update CI/CD Workflows

### `.github/workflows/publish-jvm.yml`
- Remove the cross-compilation matrix build jobs (Rust builds for Linux x86_64, Linux ARM64, macOS, Windows).
- Remove Cargo build steps, cross-compilation toolchain setup, and the `jni-libs` artifact aggregation.
- The publish step should now just run `./gradlew publish` without any native build dependency.
- The `isRemotePublication=true` property may still be needed for Maven Central publishing configuration.

### `.github/workflows/publish-android.yml`
- Remove NDK setup and Cargo/rust-android-gradle build steps.
- Android's `libzenoh_jni.so` will come from zenoh-jni-runtime's AAR, not from local Rust compilation.

### `.github/workflows/ci.yml`
- Remove Rust compilation and `cargo test` steps.
- Keep Kotlin/JVM test runs (they now depend on zenoh-jni-runtime being resolvable — may need submodule checkout step).

---

## Phase 6: Update Examples and Tests

- Verify examples still build (they depend on `zenoh-kotlin`, not directly on JNI classes).
- Run `./gradlew test` to validate correctness.
- If tests `systemProperty("java.library.path", ...)` were set, remove them — zenoh-jni-runtime handles loading.

---

## Critical Files

| File | Change |
|------|--------|
| `.gitmodules` | New — adds zenoh-java submodule |
| `settings.gradle.kts` | Remove `:zenoh-jni`, add composite build for zenoh-java |
| `build.gradle.kts` (root) | Remove rust-android-gradle plugin |
| `zenoh-kotlin/build.gradle.kts` | Add zenoh-jni-runtime dep; remove all Cargo/Rust tasks |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/` | Delete all 16+ files (if provided by zenoh-jni-runtime) |
| `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` | Delete (ZenohLoad) |
| `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` | Delete (ZenohLoad) |
| `zenoh-jni/` | Delete entire directory |
| `rust-toolchain.toml` | Delete |
| `.github/workflows/publish-jvm.yml` | Remove native build matrix |
| `.github/workflows/publish-android.yml` | Remove NDK/Cargo steps |
| `.github/workflows/ci.yml` | Remove Rust build/test steps |

---

## Verification

1. **Local build:** `./gradlew :zenoh-kotlin:compileKotlinJvm` — must succeed without Rust installed.
2. **Tests:** `./gradlew :zenoh-kotlin:jvmTest` — must pass (requires a zenoh router for integration tests).
3. **Android build:** `./gradlew :zenoh-kotlin:assembleRelease -Pandroid=true` — must succeed without NDK.
4. **Publication dry-run:** `./gradlew publish -PisRemotePublication=false` — must produce JAR/AAR without native library bundled.
5. **Dependency check:** Confirm the published POM lists `org.eclipse.zenoh:zenoh-jni-runtime` as a runtime dependency.
6. **No Rust:** `find . -name "*.rs" -o -name "Cargo.toml"` — must return nothing outside the `zenoh-java/` submodule.

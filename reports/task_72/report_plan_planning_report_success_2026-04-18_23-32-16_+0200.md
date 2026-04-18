# Plan: Make zenoh-kotlin Depend on zenoh-jni-runtime

## Context

zenoh-kotlin currently builds its own native JNI library (`zenoh-jni/` Rust crate) and ships it in the published JAR. PR #466 in zenoh-java extracts the common JNI layer into `zenoh-jni-runtime` as a standalone Maven artifact (`org.eclipse.zenoh:zenoh-jni-runtime`). This plan migrates zenoh-kotlin to consume `zenoh-jni-runtime` instead, eliminating all Rust code from zenoh-kotlin.

**Key architectural constraint (identified by adversarial review)**:
zenoh-kotlin's `io.zenoh.jni.*` classes have **two distinct layers**:
1. `private external` JNI declarations — the bridge to Rust native symbols. These are replaced by zenoh-jni-runtime's equivalent classes.
2. Public adapter methods — construct zenoh-kotlin domain objects (Publisher, Subscriber, etc.) from JNI primitive handles. These must be preserved but refactored.

Both zenoh-kotlin and zenoh-jni-runtime define classes with the same fully-qualified names (`io.zenoh.jni.JNISession`, `io.zenoh.jni.JNIConfig`, etc.). **They cannot coexist on the classpath.** Therefore, zenoh-kotlin's JNI classes must be **deleted**, and their adapter/conversion logic must be migrated into the domain classes.

**Submodule strategy**: Add zenoh-java as a git submodule for source-based local builds. Gate `includeBuild()` behind a file-existence check so ordinary clones (without submodule init) still resolve `zenoh-jni-runtime` from Maven Central.

---

## Phase 0: Pre-migration Verification (Critical)

Before any code changes, verify against the `common-jni` branch of zenoh-java (the PR #466 source):

1. **API visibility**: Confirm that zenoh-jni-runtime's JNI classes expose their JNI-bridging functions as `public` or `internal` (not `private`), so zenoh-kotlin's adapter logic can call them after migration.
2. **Class name/package match**: Confirm that zenoh-jni-runtime uses the same package `io.zenoh.jni.*` and identical class names — this confirms the deletion+redirect approach is required (not rename+delegate).
3. **ZenohLoad coverage**: Verify zenoh-jni-runtime provides `ZenohLoad` (expect/actual) for both JVM and Android platforms, replacing zenoh-kotlin's `jvmMain/Zenoh.kt` and `androidMain/Zenoh.kt`.
4. **Callback interface compatibility**: Confirm zenoh-jni-runtime's `io.zenoh.jni.callbacks.*` interfaces are functionally identical to zenoh-kotlin's 7 callback interfaces.
5. **Report failure immediately** if any capability gap is found (per task requirements).

---

## Phase 1: Add zenoh-java as Git Submodule

**Files created**: `.gitmodules`

Add zenoh-java as a submodule at path `zenoh-java`, pointing to the `common-jni` branch (source of zenoh-jni-runtime):
```
git submodule add -b common-jni https://github.com/eclipse-zenoh/zenoh-java.git zenoh-java
```

Commit the `.gitmodules` entry on the work branch.

---

## Phase 2: Update Gradle Build Configuration

### 2a. `settings.gradle.kts` (root)

- Remove `:zenoh-jni` from `include()`.
- Add conditional composite build — gate behind submodule presence so ordinary clones without submodule init still work:
  ```kotlin
  if (file("zenoh-java/settings.gradle.kts").exists()) {
      includeBuild("zenoh-java") {
          dependencySubstitution {
              substitute(module("org.eclipse.zenoh:zenoh-jni-runtime"))
                  .using(project(":zenoh-jni-runtime"))
          }
      }
  }
  ```
  With submodule initialized: resolves zenoh-jni-runtime from source.  
  Without submodule: resolves from Maven Central (requires published artifact).

### 2b. Root `build.gradle.kts`

- Remove `org.mozilla.rust-android-gradle:plugin:0.9.6` from buildscript dependencies.
- Keep `com.android.tools.build:gradle` (Android target remains in zenoh-kotlin).

### 2c. `zenoh-kotlin/build.gradle.kts`

**Add dependency** on zenoh-jni-runtime (version from `version.txt`):
```kotlin
commonMain.dependencies {
    implementation("org.eclipse.zenoh:zenoh-jni-runtime:<version>")
}
```

**Remove entirely:**
- `BuildMode` enum
- `buildZenohJni` task registration and `buildZenohJNI()` function
- `compileKotlinJvm.dependsOn("buildZenohJni")` task wiring
- `isRemotePublication`-conditional `jvmMain` resource source dirs (`../jni-libs` and `../zenoh-jni/target` paths)
- `configureCargo()` function and its invocation
- `configureAndroid()` sections that reference the Cargo plugin or NDK-specific setup (keep the Android target declaration itself)
- `tasks.whenObjectAdded { ... cargoBuild ... }` block
- `tasks.withType<Test>` block that sets `java.library.path` to the Rust target dir

**Keep**: all Maven publishing configuration, signing setup, POM metadata, Dokka setup.

---

## Phase 3: Refactor the JNI Adapter Layer (Largest Change)

**Problem**: zenoh-kotlin's `io.zenoh.jni.*` classes define the same fully-qualified names as zenoh-jni-runtime. They cannot coexist on the classpath.

**Solution**: Delete zenoh-kotlin's JNI adapter classes. Migrate their adapter logic (domain object construction from raw JNI handles) into the corresponding domain classes, which will now call zenoh-jni-runtime's `io.zenoh.jni.*` classes directly.

### What gets deleted from zenoh-kotlin:
- All 16 JNI adapter classes in `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/`:  
  `JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt`, `JNIConfig.kt`, `JNIKeyExpr.kt`, `JNILivelinessToken.kt`, `JNILogger.kt`, `JNIMatchingListener.kt`, `JNIPublisher.kt`, `JNIQuerier.kt`, `JNIQuery.kt`, `JNIQueryable.kt`, `JNISampleMissListener.kt`, `JNIScout.kt`, `JNISession.kt`, `JNISubscriber.kt`, `JNIZenohId.kt`
- All 7 callback interfaces in `.../jni/callbacks/`:  
  `JNIGetCallback.kt`, `JNIMatchingListenerCallback.kt`, `JNIOnCloseCallback.kt`, `JNIQueryableCallback.kt`, `JNISampleMissListenerCallback.kt`, `JNIScoutCallback.kt`, `JNISubscriberCallback.kt`
- Platform-specific ZenohLoad files:  
  `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (the JVM library-loading ZenohLoad implementation)  
  `zenoh-kotlin/src/androidMain/kotlin/io/zenoh/Zenoh.kt` (the Android `System.loadLibrary` implementation)

### What gets refactored in zenoh-kotlin's domain classes:

All adapter logic from deleted JNI classes migrates into the domain classes. The domain classes will import and call zenoh-jni-runtime's `io.zenoh.jni.*` directly.

**`Session.kt`** (biggest change, ~1200 lines):
- Currently holds `JNISession` instance and delegates all operations to it.
- After: holds the native session pointer (`Long`) or directly holds `io.zenoh.jni.JNISession` from zenoh-jni-runtime.
- The callback marshalling code (constructing `Sample`, `Reply`, `Hello` etc. from JNI primitive parameters) moves into `Session.kt` itself or private helpers within the session package.
- All calls to `jniSession.declarePublisher(...)` etc. become direct calls to zenoh-jni-runtime's `JNISession` methods with inline type conversion (enum ordinals, etc.).

**`Config.kt`**:
- Currently delegates to `JNIConfig.loadDefaultConfig()` etc.
- After: calls `io.zenoh.jni.JNIConfig.loadDefaultConfigViaJNI()` from zenoh-jni-runtime and manages the raw `Long` pointer inline.

**`Publisher.kt`**, **`Subscriber.kt`**, **`Queryable.kt`**, **`Query.kt`**, **`Querier.kt`**:
- Currently hold `JNI*` instances.
- After: hold raw `Long` pointers and call corresponding zenoh-jni-runtime `JNI*` classes directly for put/delete/reply/cleanup operations.

**`KeyExpr.kt`**, **`ZBytes.kt`** (if they reference JNI classes):
- Update to use zenoh-jni-runtime's JNI classes directly.

**Callback interfaces**:
- All `JNI*Callback` references in `Session.kt` etc. update to use zenoh-jni-runtime's versions from `io.zenoh.jni.callbacks.*`.
- These are `fun interface` types so the migration is a pure import change at call sites.

### ZenohLoad:
- zenoh-kotlin's commonMain `Zenoh.kt` (the expect declaration) is also deleted if zenoh-jni-runtime provides its own `ZenohLoad` expect/actual.
- Any call site in zenoh-kotlin that initializes `ZenohLoad.load()` is updated to call zenoh-jni-runtime's equivalent entry point.

---

## Phase 4: Remove All Rust Code

- Delete the entire `zenoh-jni/` directory (Rust source files, `Cargo.toml`, `Cargo.lock`, `build.rs`).
- Delete `rust-toolchain.toml` at the repo root.
- Verify: `find . -name "*.rs" -o -name "Cargo.toml"` should return nothing outside the `zenoh-java/` submodule.

---

## Phase 5: Update `examples/build.gradle.kts`

- Remove the `CompileZenohJNI` task that invokes `cargo build --manifest-path ../zenoh-jni/Cargo.toml`.
- Remove the `-Djava.library.path=../zenoh-jni/target/release` system property from example execution tasks.
- Native library loading is now handled by zenoh-jni-runtime's `ZenohLoad`.

---

## Phase 6: Update CI Workflows

### `.github/workflows/ci.yml`
- Remove: Rust toolchain setup (`rustup show`, `rustfmt`, `clippy`), `cargo fmt`, `cargo clippy`, `cargo test`, `cargo build` steps.
- Add `submodules: recursive` to the `actions/checkout@v4` step — CI must initialize the zenoh-java submodule to resolve zenoh-jni-runtime from source during the build.
- Note: Since the composite build resolves zenoh-jni-runtime from the submodule source (which itself builds Rust code from `zenoh-java/zenoh-jni`), Rust toolchain is still needed in CI — but it belongs to zenoh-java's build, not zenoh-kotlin's. Ensure `rustup` is installed for the composite build's native compilation step, or configure CI to resolve zenoh-jni-runtime from a published Maven snapshot instead (better long-term).

### `.github/workflows/publish-jvm.yml`
- Remove: the 6-platform cross-compilation matrix (Linux x86_64/ARM64, macOS x86_64/ARM64, Windows x86_64/ARM64), all `cargo build` steps, the `jni-libs` artifact download/aggregation job.
- The publish step becomes: `./gradlew publish -PisRemotePublication=true` without any pre-built native artifact requirement (zenoh-jni-runtime ships its own native libraries).
- Remove the `isRemotePublication` Gradle property usage since native bundling is zenoh-jni-runtime's responsibility.

### `.github/workflows/publish-android.yml`
- Remove: NDK setup (`nttld/setup-ndk`), all `rustup target add` steps for Android ABIs.
- Remove: Cargo/rust-android-gradle cross-compilation steps.
- zenoh-jni-runtime's AAR provides Android native libraries.

---

## Critical Files

| File/Path | Change |
|-----------|--------|
| `.gitmodules` | New — adds zenoh-java submodule (`common-jni` branch) |
| `settings.gradle.kts` | Remove `:zenoh-jni`; add conditional composite build for zenoh-java |
| `build.gradle.kts` (root) | Remove `rust-android-gradle` plugin from buildscript |
| `zenoh-kotlin/build.gradle.kts` | Add zenoh-jni-runtime dep; remove all Cargo/Rust tasks, resource config, `BuildMode` enum, `isRemotePublication` native logic |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/` | Delete all 16 JNI adapter classes |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/` | Delete all 7 callback interfaces |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt` | Major refactor: inline JNISession adapter logic; call zenoh-jni-runtime's JNI classes |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Config.kt` | Refactor: call zenoh-jni-runtime's JNIConfig directly |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/Publisher.kt` | Hold raw `Long` ptr; call zenoh-jni-runtime's JNIPublisher |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/Subscriber.kt` | Update JNI class reference |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/query/Query.kt` | Hold raw `Long` ptr; use zenoh-jni-runtime's JNIQuery |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/query/Queryable.kt` | Update JNI class reference |
| (other domain classes referencing JNI*) | Update all `io.zenoh.jni.*` references to use zenoh-jni-runtime's versions |
| `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` | Delete (ZenohLoad provided by zenoh-jni-runtime) |
| `zenoh-kotlin/src/androidMain/kotlin/io/zenoh/Zenoh.kt` | Delete (ZenohLoad provided by zenoh-jni-runtime) |
| `zenoh-jni/` | Delete entire directory |
| `rust-toolchain.toml` | Delete |
| `examples/build.gradle.kts` | Remove `CompileZenohJNI` task and `java.library.path` references |
| `.github/workflows/ci.yml` | Remove Rust steps; add submodule checkout |
| `.github/workflows/publish-jvm.yml` | Remove cross-compilation matrix and artifact aggregation |
| `.github/workflows/publish-android.yml` | Remove NDK/Cargo steps |

---

## Verification

1. **No Rust code in zenoh-kotlin**: `find . -name "*.rs" -o -name "Cargo.toml"` returns nothing outside `zenoh-java/` submodule.
2. **Compilation without local Rust** (submodule initialized): `./gradlew :zenoh-kotlin:compileKotlinJvm` succeeds.
3. **JVM tests**: `./gradlew :zenoh-kotlin:jvmTest` passes (requires a zenoh router).
4. **POM check**: `./gradlew generatePomFileForMavenJvmPublication` — confirm `org.eclipse.zenoh:zenoh-jni-runtime` appears as a runtime dependency.
5. **No classpath duplicates**: `./gradlew :zenoh-kotlin:dependencies --configuration jvmRuntimeClasspath` — no duplicate `io.zenoh.jni.*` classes.
6. **Examples build**: `./gradlew :examples:shadowJar` builds without any Cargo tasks.
7. **API unchanged**: All public types in `io.zenoh.*` (Session, Config, Publisher, Subscriber, Querier, Queryable, Query, KeyExpr, ZBytes, etc.) retain their existing signatures.

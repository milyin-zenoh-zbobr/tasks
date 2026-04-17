# Plan: Make zenoh-kotlin Use zenoh-jni-runtime from zenoh-java

## Context

The PR https://github.com/eclipse-zenoh/zenoh-java/pull/465 (branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`, worktree at `/data/home/skynet/tasks/base/workspaces/zenoh-java/task-68/zenoh-java`) extracts a shared `zenoh-jni-runtime` Kotlin/multiplatform module from zenoh-java. This module exposes public, primitive-only JNI adapters (`JNISession`, `JNIConfig`, `JNIKeyExpr`, `JNIScout`, etc.) plus `ZenohLoad`, `Target`, and `ZError` — classes that zenoh-kotlin currently duplicates in its own `io.zenoh.jni` package.

The goal is to:
1. Add zenoh-java as a git submodule and use a Gradle composite build to consume `zenoh-jni-runtime`
2. Delete zenoh-kotlin's duplicated JNI wrapper layer (except `JNIZBytes`, see note below)
3. Delete zenoh-kotlin's `zenoh-jni/` Rust crate entirely — the native library comes from zenoh-java's `zenoh-jni/`
4. Update all callers (Session.kt, Config.kt, Publisher.kt, Query.kt, etc.) to call zenoh-jni-runtime's public primitive API

**Why composite build / submodule**: zenoh-jni-runtime is not yet released to Maven Central, so a local submodule + `includeBuild` is the only option during development. This is the same pattern zenoh-java uses for internal module references.

**Closest analog**: zenoh-java's own `zenoh-java/build.gradle.kts` and `Session.kt` show exactly how to depend on zenoh-jni-runtime and call its primitive API.

**Critical JNIZBytes note**: `JNIZBytes.kt` exists in zenoh-kotlin (`io.zenoh.jni.JNIZBytes`) but NOT in `zenoh-jni-runtime`. It IS in the zenoh-java facade module. The native functions `Java_io_zenoh_jni_JNIZBytes_serializeViaJNI` / `...deserializeViaJNI` are implemented in zenoh-java's `zenoh-jni/` Rust crate. Since zenoh-kotlin will use that same Rust crate, **keep** `JNIZBytes.kt` in zenoh-kotlin.

---

## Phase 1: Add zenoh-java as Git Submodule

- Run `git submodule add <zenoh-java-repo-url> zenoh-java` from the zenoh-kotlin root
- Pin the submodule to the PR branch HEAD (`c4ec1d89c246a76edd03128593fd34f6641c405d`)
- Commit `.gitmodules` and the submodule reference

The zenoh-java submodule lives at `zenoh-kotlin/zenoh-java/`. The native Rust crate used by both projects will be at `zenoh-kotlin/zenoh-java/zenoh-jni/`.

---

## Phase 2: Gradle Build Configuration

### 2a. `settings.gradle.kts` (root)

- Remove `include(":zenoh-jni")` — the local Rust crate subproject is gone
- Add an `includeBuild("zenoh-java")` block with dependency substitution:
  ```kotlin
  includeBuild("zenoh-java") {
      dependencySubstitution {
          substitute(module("org.eclipse.zenoh:zenoh-jni-runtime"))
              .using(project(":zenoh-jni-runtime"))
      }
  }
  ```

### 2b. Root `build.gradle.kts`

- Remove from `buildscript.dependencies`: `classpath("org.mozilla.rust-android-gradle:plugin:0.9.6")`
- Remove from `plugins`: `id("org.mozilla.rust-android-gradle.rust-android") version "0.9.6" apply false`
  (Android Rust building is now handled by the zenoh-java composite build)

### 2c. `zenoh-kotlin/build.gradle.kts`

**Remove:**
- The `buildZenohJni` Gradle task and `buildZenohJNI` helper function
- The `BuildMode` enum (use a plain string `val buildMode = if (release) "release" else "debug"`)
- The `configureAndroid()` and `configureCargo()` functions
- The `org.mozilla.rust-android-gradle.rust-android` plugin application
- The `tasks.whenObjectAdded { if (mergeDebugJniLibFolders || mergeReleaseJniLibFolders) dependsOn("cargoBuild") }` block
- The `jvmMain` resource `srcDir` pointing to `../zenoh-jni/target/...` (resources come from zenoh-jni-runtime via dependency)
- The `jvmTest` resource `srcDir` pointing to `../zenoh-jni/target/...` (same reason)
- The `tasks.withType<Test> { systemProperty("java.library.path", ...) }` block — the zenoh-jni-runtime `ZenohLoad` loads the library from classpath resources, not from `java.library.path`

**Add:**
- `zenoh-jni-runtime` as a dependency in `commonMain`:
  ```kotlin
  api("org.eclipse.zenoh:zenoh-jni-runtime:${rootProject.version}")
  ```
- Wire compile to the included build's native build task using the Gradle composite build API:
  ```kotlin
  tasks.named("compileKotlinJvm") {
      dependsOn(gradle.includedBuild("zenoh-java").task(":zenoh-jni-runtime:buildZenohJni"))
  }
  ```

**Keep (Android):** The `configureAndroid()` block that configures the `android {}` extension is still needed (namespace, compileSdk, minSdk, etc.) — only the Cargo parts inside it are removed. Android NDK library loading is now handled by zenoh-jni-runtime.

### 2d. `examples/build.gradle.kts`

- Update `java.library.path` in each `JavaExec` task from `../zenoh-jni/target/release` to `../zenoh-java/zenoh-jni/target/release`
- Update (or replace) the `CompileZenohJNI` task to use the composite build:
  ```kotlin
  tasks.register("CompileZenohJNI") {
      dependsOn(gradle.includedBuild("zenoh-java").task(":zenoh-jni-runtime:buildZenohJni"))
  }
  ```

---

## Phase 3: Remove Duplicate Classes

### 3a. Delete zenoh-kotlin's JNI wrapper layer

Delete all files in `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/` **except `JNIZBytes.kt`**:
- `JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt`, `JNIConfig.kt`, `JNIKeyExpr.kt`
- `JNILiveliness.kt`, `JNILivelinessToken.kt`, `JNIMatchingListener.kt`, `JNIPublisher.kt`
- `JNIQuerier.kt`, `JNIQueryable.kt`, `JNIQuery.kt`, `JNISampleMissListener.kt`
- `JNIScout.kt`, `JNISession.kt`, `JNISubscriber.kt`, `JNIZenohId.kt`
- `callbacks/JNIGetCallback.kt`, `JNIMatchingListenerCallback.kt`, `JNIOnCloseCallback.kt`, `JNIQueryableCallback.kt`, `JNISampleMissListenerCallback.kt`, `JNIScoutCallback.kt`, `JNISubscriberCallback.kt`

**Keep `JNIZBytes.kt`**: native methods are provided by zenoh-java's `zenoh-jni` Rust crate.

### 3b. Delete duplicate shared classes

- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt` — provided by zenoh-jni-runtime
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (the ZenohLoad JVM actual) — provided by zenoh-jni-runtime
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt` — provided by zenoh-jni-runtime (now `public`)
- `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` (the ZenohLoad Android actual) — provided by zenoh-jni-runtime

### 3c. Update `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt`

Remove the `internal expect object ZenohLoad` declaration at the bottom of this file. `ZenohLoad` is now `public expect object ZenohLoad` from zenoh-jni-runtime. The usages of `ZenohLoad` in `scout()` and `tryInitLogFromEnv()` remain as-is — they resolve to zenoh-jni-runtime's class.

---

## Phase 4: Update `Config.kt`

`Config.kt` uses `JNIConfig` factory methods. In zenoh-jni-runtime, these methods return a raw `Long` pointer (not a `Config` object), and `JNIConfig` constructor takes a `Long`. Update all factory calls:

- `JNIConfig.loadDefaultConfig()` → now returns `Long`; wrap as `Config(JNIConfig(JNIConfig.loadDefaultConfig()))`
- `JNIConfig.loadConfigFile(path.toString())` → returns `Long`; wrap in `runCatching { Config(JNIConfig(...)) }`
- `JNIConfig.loadJsonConfig(raw)`, `loadYamlConfig(raw)`, `loadJson5Config(raw)` → same pattern
- `jniConfig.getJson(key)` → zenoh-jni-runtime's method throws `ZError` (not Result); wrap in `runCatching`
- `jniConfig.insertJson5(key, value)` → same; wrap in `runCatching`

The `internal val jniConfig: JNIConfig` field on `Config` keeps the same type, now resolved from zenoh-jni-runtime.

---

## Phase 5: Refactor `Session.kt`

This is the largest change. zenoh-kotlin's `JNISession` (552 lines) had "fat" methods that accepted domain objects. zenoh-jni-runtime's `JNISession` is a thin wrapper with primitive-only parameters.

**Session opening:**
- Change from: `val jni = JNISession(); jni.open(config)` (where open accepted `Config`)
- Change to: `jniSession = JNISession.open(config.jniConfig.ptr)` (static factory method accepting `Long`)
- The field `internal var jniSession: JNISession?` stays; type now resolves to zenoh-jni-runtime's public `JNISession`

**For each operation** (`declarePublisher`, `declareSubscriber`, `declareQueryable`, `get`, `put`, `delete`, `declareKeyExpr`, `undeclareKeyExpr`, `zid`, `peersZid`, `routersZid`, `declareAdvancedPublisher`, `declareAdvancedSubscriber`):
- Inline the callback assembly that was previously inside JNISession
- Extract primitives from domain objects (KeyExpr → ptr+string, QoS → congestionControl.value+priority.value+express, Encoding → id+schema, etc.)
- Call zenoh-jni-runtime's `JNISession` methods directly with primitives
- Reconstruct domain objects from the returned primitives

**Liveliness operations** (previously via `JNILiveliness`):
- In zenoh-jni-runtime, `JNILiveliness` remains a separate object (not merged into JNISession)
- `Liveliness.kt` which calls these operations should be updated to call `JNILiveliness.declareTokenViaJNI(sessionPtr, keyExprPtr, keyExprString)` etc. directly with primitives
- The `sessionPtr` is accessed via `session.jniSession?.sessionPtr`

---

## Phase 6: Update Domain Classes

Follow the same primitive-extraction pattern used in zenoh-java's refactored classes:

**`Publisher.kt`**: Change `jniPublisher?.put(payload, encoding, attachment)` → call with `payload.bytes`, `encoding.id`, `encoding.schema`, `attachment?.into()?.bytes`.

**`Query.kt`**: Change `replySuccess/replyError/replyDelete` to pass primitives (keyExprPtr, keyExprString, payload bytes, encoding id/schema, etc.).

**`Querier.kt`**: Inline `JNIGetCallback` assembly; call `jniQuerier?.get(...)` with primitives.

**`AdvancedPublisher.kt`**: Convert domain objects to primitives for `put`/`delete`; inline `JNIMatchingListenerCallback` assembly.

**`AdvancedSubscriber.kt`**: Inline `JNISubscriberCallback` and `JNISampleMissListenerCallback` assembly.

**`KeyExpr.kt`**: `jniKeyExpr: JNIKeyExpr?` field type now resolves to zenoh-jni-runtime's public `JNIKeyExpr`.

**`Logger.kt`**: Update `Logger.startLogsViaJNI(filter)` to call `JNILogger.startLogs(filter)` if the method name changed; verify against zenoh-jni-runtime's `JNILogger`.

All close-only classes (`Subscriber.kt`, `Queryable.kt`, `LivelinessToken.kt`, `Scout.kt`, `MatchingListener.kt`, `SampleMissListener.kt`): the field type changes from zenoh-kotlin's `internal` JNI class to zenoh-jni-runtime's `public` JNI class; no functional logic change needed.

---

## Phase 7: Remove Rust Code

1. Delete the entire `zenoh-jni/` directory (Rust crate: `Cargo.toml`, `src/`, `Cargo.lock`, `build.rs` if present)
2. Delete `rust-toolchain.toml` from the zenoh-kotlin root — Rust toolchain is managed in zenoh-java

---

## Phase 8: Update CI Workflows

### `.github/workflows/ci.yml`

- Replace the `actions/checkout@v4` step with one that initializes submodules:
  ```yaml
  - uses: actions/checkout@v4
    with:
      submodules: recursive
  ```
- Remove steps: `Cargo Format`, `Clippy Check`, `Check for feature leaks`, `Build Zenoh-JNI` (all operating on `zenoh-jni/`)
- Keep the `Install Rust toolchain` step — needed for the Rust build triggered by Gradle
- The native library is now built automatically by the `compileKotlinJvm` → `buildZenohJni` task chain

### `.github/workflows/publish-jvm.yml`

- Add `submodules: recursive` to the checkout step
- Remove direct `cargo build` steps that reference `zenoh-jni/`; the native build is triggered via Gradle task dependency on the included build
- Update `JNI_LIB_PATHS` or similar references to point to `zenoh-java/zenoh-jni/target/` if used
- Remove the matrix cross-compilation jobs for native libs — zenoh-kotlin's JVM publication no longer packages native libs (they come from zenoh-jni-runtime)
  - **Note**: The worker should verify the exact publish flow by comparing with zenoh-java's publish-jvm.yml

### `.github/workflows/publish-android.yml`

- Add `submodules: recursive` to the checkout step:
  ```yaml
  - uses: actions/checkout@v4
    with:
      ref: ${{ inputs.branch }}
      submodules: recursive
  ```
- Remove any `cargo build` steps referencing `zenoh-jni/` (Cargo build is handled by Gradle via included build)

---

## File Change Summary

| Action | Files |
|--------|-------|
| **Add** | `.gitmodules`, `zenoh-java/` (submodule ref) |
| **Delete** | `zenoh-jni/` (entire Rust crate), `rust-toolchain.toml`, all `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/*.kt` except `JNIZBytes.kt`, all `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/*.kt`, `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`, `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (ZenohLoad actual), `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt`, `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` |
| **Modify** | `settings.gradle.kts`, `build.gradle.kts` (root), `zenoh-kotlin/build.gradle.kts`, `examples/build.gradle.kts`, `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt` (remove `expect object ZenohLoad`), `Config.kt`, `Session.kt`, `Publisher.kt`, `AdvancedPublisher.kt`, `AdvancedSubscriber.kt`, `Query.kt`, `Querier.kt`, `Logger.kt`, `Liveliness.kt`, `KeyExpr.kt`, `.github/workflows/ci.yml`, `.github/workflows/publish-jvm.yml`, `.github/workflows/publish-android.yml` |

---

## Verification

1. `./gradlew :zenoh-kotlin:compileKotlinJvm` — triggers `buildZenohJni` from the included build; should compile without Rust errors or missing class errors
2. `./gradlew :zenoh-kotlin:jvmTest` — all tests should pass; native library is loaded from zenoh-jni-runtime's classpath resources
3. `./gradlew :examples:ZPub` — should run successfully with updated `java.library.path`
4. Verify no remaining references to deleted files: `grep -r "zenoh-jni" settings.gradle.kts build.gradle.kts zenoh-kotlin/build.gradle.kts` (except the submodule path)
5. Verify `JNIZBytes` methods still resolve: compile and run ZBytes-related tests

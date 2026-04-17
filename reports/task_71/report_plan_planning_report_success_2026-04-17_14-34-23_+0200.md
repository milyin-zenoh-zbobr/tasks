# Plan: Make zenoh-kotlin Use zenoh-jni-runtime from zenoh-java

## Context

PR https://github.com/eclipse-zenoh/zenoh-java/pull/465 (branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`, worktree at `/data/home/skynet/tasks/base/workspaces/zenoh-java/task-68/zenoh-java`) creates a new `zenoh-jni-runtime` Kotlin multiplatform module in zenoh-java. This module exposes **public, primitive-only JNI adapters** (JNISession, JNIConfig, JNIKeyExpr, JNILiveliness, etc.) plus `ZenohLoad`, `Target`, and `ZError`, which zenoh-kotlin currently duplicates in its own `io.zenoh.jni` package.

The goal: consume `zenoh-jni-runtime` via Gradle composite build, delete zenoh-kotlin's duplicated JNI wrappers, delete the local `zenoh-jni/` Rust crate, and inline primitive extraction in the callers (Session.kt, Liveliness.kt, etc.).

**Closest analog**: zenoh-java's own Session.kt and other facade classes (post-PR) show exactly how to call the primitive JNI runtime API.

---

## Verified API Shapes (from actual files in zenoh-jni-runtime)

These are the **actual** signatures — previous plan reviews contained incorrect claims:

- `JNIConfig(val ptr: Long)` — constructor; factory methods `loadDefaultConfig(): Long`, `loadConfigFile(path: String): Long`, `loadJsonConfig(raw: String): Long`, `loadYamlConfig(raw: String): Long`, `loadJson5Config(raw: String): Long`; instance methods `getJson(key): String`, `insertJson5(key, value)`, `close()`
- `JNISession.open(configPtr: Long): JNISession` — takes the raw config pointer, **not** a `JNIConfig` object
- `JNILiveliness` — **separate `public object`** in zenoh-jni-runtime with `declareTokenViaJNI(sessionPtr, keyExprPtr, keyExprString): Long`, `declareSubscriberViaJNI(...)`, `getViaJNI(...)`
- `JNIZBytes.kt` — **does NOT exist in zenoh-jni-runtime**; it is in the zenoh-java facade module only. zenoh-kotlin must **keep its own `JNIZBytes.kt`** (the Rust function is present in zenoh-java's `zenoh-jni` crate with the same JNI mangled name).
- `ZenohLoad` — `public expect object ZenohLoad` in zenoh-jni-runtime; JVM and Android actuals are provided.
- `Target` — `public enum class Target` in zenoh-jni-runtime (jvmMain).
- `ZError` — `class ZError` in `io.zenoh.exceptions` package of zenoh-jni-runtime.
- **No JNILogger in zenoh-jni-runtime** — zenoh-kotlin's `internal class Logger` (with `external fun startLogsViaJNI`) stays as-is; the Rust function `Java_io_zenoh_Logger_00024Companion_startLogsViaJNI` is present in zenoh-java's `zenoh-jni` crate.

---

## Phase 1: Add zenoh-java as Git Submodule

- Add `https://github.com/eclipse-zenoh/zenoh-java.git` as submodule at path `zenoh-java/`
- Pin to PR branch HEAD commit (`c4ec1d89c246a76edd03128593fd34f6641c405d`)
- Commit `.gitmodules` and the submodule entry

The native Rust crate and `zenoh-jni-runtime` are then available at `zenoh-java/zenoh-jni/` and `zenoh-java/zenoh-jni-runtime/` respectively.

---

## Phase 2: Gradle Build Configuration

### 2a. `settings.gradle.kts` (root)

- Remove `include(":zenoh-jni")`
- Add `includeBuild("zenoh-java")` with dependency substitution, **conditioned on non-remote publication** so that during Maven Central release builds the artifact is resolved from Maven Central instead:
  ```kotlin
  val isRemotePublication = gradle.startParameter.projectProperties["remotePublication"]?.toBoolean() == true
  if (!isRemotePublication) {
      includeBuild("zenoh-java") {
          dependencySubstitution {
              substitute(module("org.eclipse.zenoh:zenoh-jni-runtime"))
                  .using(project(":zenoh-jni-runtime"))
          }
      }
  }
  ```

### 2b. Root `build.gradle.kts`

- Remove `classpath("org.mozilla.rust-android-gradle:plugin:0.9.6")` from `buildscript.dependencies`
- Remove `id("org.mozilla.rust-android-gradle.rust-android") version "0.9.6" apply false` from `plugins`

### 2c. `zenoh-kotlin/build.gradle.kts`

**Remove:**
- The `buildZenohJni` task and `buildZenohJNI` helper, `BuildMode` enum
- The `configureAndroid()` Cargo plugin portion and `configureCargo()` function (keep the pure `android {}` configuration block: namespace, compileSdk, minSdk, etc.)
- `org.mozilla.rust-android-gradle.rust-android` plugin application
- `tasks.whenObjectAdded { ... cargoBuild ... }` block
- `jvmMain` and `jvmTest` resource `srcDir` pointing to `../zenoh-jni/target/...`
- `tasks.withType<Test> { systemProperty("java.library.path", ...) }` — `ZenohLoad` in zenoh-jni-runtime loads the library from classpath resources

**Add:**
- `zenoh-jni-runtime` as `api` dependency in `commonMain`
- Task wiring to trigger the native build from the included build before compilation:
  ```kotlin
  tasks.named("compileKotlinJvm") {
      dependsOn(gradle.includedBuild("zenoh-java").task(":zenoh-jni-runtime:buildZenohJni"))
  }
  ```

### 2d. `examples/build.gradle.kts`

- Replace `cargo build --manifest-path ../zenoh-jni/Cargo.toml` in `CompileZenohJNI` with composite build task dependency: `dependsOn(gradle.includedBuild("zenoh-java").task(":zenoh-jni-runtime:buildZenohJni"))`
- Update `java.library.path` in each `JavaExec` task from `../zenoh-jni/target/release` to `../zenoh-java/zenoh-jni/target/release`

---

## Phase 3: Delete Duplicate Classes

### 3a. Delete all files in `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/` EXCEPT `JNIZBytes.kt`

Files to delete:
`JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt`, `JNIConfig.kt`, `JNIKeyExpr.kt`, `JNILiveliness.kt`, `JNILivelinessToken.kt`, `JNIMatchingListener.kt`, `JNIPublisher.kt`, `JNIQuerier.kt`, `JNIQueryable.kt`, `JNIQuery.kt`, `JNISampleMissListener.kt`, `JNIScout.kt`, `JNISession.kt`, `JNISubscriber.kt`, `JNIZenohId.kt`, and the entire `callbacks/` subdirectory.

**Keep `JNIZBytes.kt`** — the native function exists in zenoh-java's `zenoh-jni` crate; no equivalent in zenoh-jni-runtime.

### 3b. Delete duplicate shared classes (provided by zenoh-jni-runtime)

- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (the ZenohLoad JVM actual)
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt`
- `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` (ZenohLoad Android actual)

### 3c. Update `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt`

Remove `internal expect object ZenohLoad` declaration at the bottom. The public `ZenohLoad` from zenoh-jni-runtime replaces it. All usages in `scout()` and `tryInitLogFromEnv()` remain as-is.

---

## Phase 4: Update `Config.kt`

The internal `JNIConfig` field and all factory calls now use zenoh-jni-runtime's API (which returns raw `Long` pointers from factory methods):

- `JNIConfig.loadDefaultConfig()` returns `Long` → wrap: `Config(JNIConfig(JNIConfig.loadDefaultConfig()))`
- `JNIConfig.loadConfigFile(path.toString())` returns `Long` → same wrapping pattern
- `JNIConfig.loadJsonConfig(raw)`, `loadYamlConfig(raw)`, `loadJson5Config(raw)` → same
- `jniConfig.getJson(key)` throws `ZError` (no Result wrapper) → existing `runCatching` call in Config.kt handles this
- `jniConfig.insertJson5(key, value)` same

**Note**: `Config.fromJson5(raw: String)` must be preserved using `JNIConfig.loadJson5Config(raw)` (the method exists in zenoh-jni-runtime).

---

## Phase 5: Refactor `Session.kt`

zenoh-kotlin's `JNISession` (old) accepted domain objects; zenoh-jni-runtime's `JNISession` accepts only primitives. The `Session.kt` must inline the conversion logic.

**Session open/close:**
- Replace `JNISession()` constructor + `open(config)` with `JNISession.open(config.jniConfig.ptr)` (static factory taking `Long`)
- `jniSession.close()` stays (same method name in runtime)
- Field `internal var jniSession: JNISession?` type now resolves to zenoh-jni-runtime's public class

**For each operation** (`declarePublisher`, `declareSubscriber`, `declareQueryable`, `get`, `put`, `delete`, `declareKeyExpr`, `undeclareKeyExpr`, `zid`, `peersZid`, `routersZid`, `declareAdvancedPublisher`, `declareAdvancedSubscriber`): inline the callback assembly previously inside the old JNISession, extract primitives from domain objects (KeyExpr → ptr+string, QoS → congestionControl.value+priority.value+express, Encoding → id+schema), then call the `xyzViaJNI(...)` method on the JNISession instance with all primitives.

Reference zenoh-java's `Session.kt` (same PR) for the exact primitive extraction and callback patterns.

---

## Phase 6: Refactor `Liveliness.kt`

Replace calls to deleted `JNILiveliness.declareToken(jniSession, keyExpr)` (old domain-object API) with inline calls to zenoh-jni-runtime's `JNILiveliness.declareTokenViaJNI(sessionPtr, keyExprPtr, keyExprString)` and wrap result in `LivelinessToken(JNILivelinessToken(ptr))`.

Same for `JNILiveliness.declareSubscriberViaJNI(...)` and `JNILiveliness.getViaJNI(...)`.

Access the session pointer via `session.jniSession?.sessionPtr` (already used in the existing code).

---

## Phase 7: Update Other Domain Classes

Follow the primitive-extraction pattern from zenoh-java's refactored classes:

- **`Publisher.kt`**: pass `payload.bytes`, `encoding.id`, `encoding.schema`, `attachment?.into()?.bytes` to `jniPublisher.putViaJNI(...)` / `deleteViaJNI(...)`
- **`Query.kt`**: pass primitives for `replySuccess`, `replyError`, `replyDelete`
- **`Querier.kt`**: inline `JNIGetCallback` assembly; call `jniQuerier.getViaJNI(...)` with primitives
- **`AdvancedPublisher.kt`**: convert to primitives; inline `JNIMatchingListenerCallback` assembly
- **`AdvancedSubscriber.kt`**: inline `JNISubscriberCallback` and `JNISampleMissListenerCallback` assembly
- **`KeyExpr.kt`**: field type `jniKeyExpr: JNIKeyExpr?` now resolves to zenoh-jni-runtime's public class
- **`Subscriber.kt`, `Queryable.kt`, `LivelinessToken.kt`, `Scout.kt`, `MatchingListener.kt`, `SampleMissListener.kt`**: field type updated; no logic change (only `close()` called)
- **`Logger.kt`**: unchanged — it's `internal` and not in `jni/`; its `external fun startLogsViaJNI` resolves to the Rust function in zenoh-java's crate

---

## Phase 8: Delete Rust Code

- Delete entire `zenoh-jni/` directory (Rust crate)
- Delete `rust-toolchain.toml` from zenoh-kotlin root

---

## Phase 9: Update CI Workflows

### `.github/workflows/ci.yml`
- Add `submodules: recursive` to the checkout step
- Remove Rust-specific steps: `Cargo Format`, `Clippy Check`, `Check for feature leaks`, direct `cargo build` for `zenoh-jni/`
- Keep `Install Rust toolchain` step (needed for the native build triggered by Gradle)

### `.github/workflows/publish-jvm.yml`
- Add `submodules: recursive` to checkout step
- Remove cross-compilation matrix jobs and `cargo/cross build` steps for zenoh-kotlin's old `zenoh-jni/`; native libs now come from zenoh-jni-runtime (already packages native libs)
- Keep `./gradlew publishJvmPublicationToSonatypeRepository -PremotePublication=true`; with `remotePublication=true`, the composite build substitution is skipped and `zenoh-jni-runtime` is resolved from Maven Central (where it was already published by zenoh-java's pipeline)

### `.github/workflows/publish-android.yml`
- Add `submodules: recursive` to checkout step
- Remove Cargo build steps for `zenoh-jni/`; Gradle task dependency on zenoh-jni-runtime handles the native build

---

## File Change Summary

| Action | Files |
|--------|-------|
| **Add** | `.gitmodules`, `zenoh-java/` (submodule) |
| **Delete** | `zenoh-jni/` (Rust crate), `rust-toolchain.toml`, all `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/*.kt` except `JNIZBytes.kt`, all `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/*.kt`, `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`, `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt`, `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt`, `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` |
| **Modify** | `settings.gradle.kts`, `build.gradle.kts` (root), `zenoh-kotlin/build.gradle.kts`, `examples/build.gradle.kts`, `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt`, `Config.kt`, `Session.kt`, `Publisher.kt`, `AdvancedPublisher.kt`, `AdvancedSubscriber.kt`, `Query.kt`, `Querier.kt`, `Liveliness.kt`, `KeyExpr.kt`, `.github/workflows/ci.yml`, `.github/workflows/publish-jvm.yml`, `.github/workflows/publish-android.yml` |

---

## Publication Strategy

- **Local dev / CI**: `includeBuild("zenoh-java")` active (submodule present, `remotePublication` not set). Gradle builds zenoh-jni-runtime natively. zenoh-kotlin resolves `zenoh-jni-runtime` from the local composite build.
- **Maven Central publication**: `remotePublication=true` flag skips the `includeBuild` substitution in `settings.gradle.kts`. zenoh-kotlin's publish workflow resolves `zenoh-jni-runtime` from Maven Central (zenoh-java's own publish pipeline publishes it there first). No double-publishing.

---

## Verification

1. `./gradlew :zenoh-kotlin:compileKotlinJvm` — triggers `:zenoh-jni-runtime:buildZenohJni` from included build; should compile without Rust errors or missing class errors
2. `./gradlew :zenoh-kotlin:jvmTest` — all tests pass; native library loaded by zenoh-jni-runtime's ZenohLoad
3. `./gradlew :examples:ZPub` — runs with updated `java.library.path`
4. Verify `JNIZBytes` still works: run ZBytes serialization/deserialization tests
5. `grep -r "zenoh-jni" settings.gradle.kts build.gradle.kts zenoh-kotlin/build.gradle.kts` — only the submodule path should appear

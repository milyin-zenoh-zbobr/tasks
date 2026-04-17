# Implementation Plan: Make zenoh-kotlin Use zenoh-jni-runtime from zenoh-java

## Context and Rationale

PR https://github.com/eclipse-zenoh/zenoh-java/pull/465 (branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`, HEAD `c4ec1d89c246a76edd03128593fd34f6641c405d`) introduces a reusable `zenoh-jni-runtime` Kotlin multiplatform module in zenoh-java. This module exports all JNI wrapper classes as **public** and provides the native library loading logic. zenoh-kotlin currently duplicates all of these internally. The goal is to consume `zenoh-jni-runtime` via Gradle composite build, delete zenoh-kotlin's duplicated JNI wrappers and its own Rust crate.

**Closest analog**: zenoh-java's own facade classes (post-PR 465) show the exact pattern for calling the runtime primitive JNI API.

---

## Verified API Shapes (from actual source files in PR 465)

These are the **actual** signatures — confirmed by reading the source files directly.

### JNIConfig (zenoh-jni-runtime)
```
class JNIConfig(internal val ptr: Long)
companion object:
  loadDefault(): JNIConfig
  loadFromFile(path: String): JNIConfig
  loadFromJson(rawConfig: String): JNIConfig
  loadFromYaml(rawConfig: String): JNIConfig
  // NO loadFromJson5() — zenoh-java maps fromJson5 to loadFromJson()
instance:
  getJson(key: String): String          // throws ZError directly (no Result)
  insertJson5(key: String, value: String) // throws ZError directly (no Result)
  close()
```

### JNISession (zenoh-jni-runtime)
```
class JNISession(val sessionPtr: Long)   // sessionPtr is plain Long, NOT AtomicLong
companion:
  open(config: JNIConfig): JNISession    // takes JNIConfig object, NOT a Long

Liveliness methods are on JNISession directly (NO separate JNILiveliness object):
  declareLivelinessToken(jniKeyExpr: JNIKeyExpr?, keyExprString: String): JNILivelinessToken
  declareLivelinessSubscriber(jniKeyExpr, keyExprString, callback: JNISubscriberCallback, history: Boolean, onClose: JNIOnCloseCallback): JNISubscriber
  livelinessGet(jniKeyExpr, keyExprString, callback: JNIGetCallback, timeoutMs: Long, onClose: JNIOnCloseCallback)

All other methods (declarePublisher, declareSubscriber, declareQueryable, declareQuerier, get, put, delete, declareKeyExpr, undeclareKeyExpr, getZid, getPeersZid, getRoutersZid, declareAdvancedPublisher, declareAdvancedSubscriber) accept only primitives.
```

### JNIPublisher / JNIAdvancedPublisher (zenoh-jni-runtime)
```
put(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?)
delete(attachment: ByteArray?)
// JNIAdvancedPublisher additionally: declareMatchingListener, declareBackgroundMatchingListener, getMatchingStatus
```

### JNIQuery (zenoh-jni-runtime)
```
replySuccess(jniKeyExpr: JNIKeyExpr?, keyExprString: String, payload: ByteArray, encodingId: Int, encodingSchema: String?, timestampEnabled: Boolean, timestampNtp64: Long, attachment: ByteArray?, qosExpress: Boolean)
replyError(errorPayload: ByteArray, encodingId: Int, encodingSchema: String?)
replyDelete(jniKeyExpr: JNIKeyExpr?, keyExprString: String, timestampEnabled: Boolean, timestampNtp64: Long, attachment: ByteArray?, qosExpress: Boolean)
```

### JNIQuerier (zenoh-jni-runtime)
```
get(jniKeyExpr: JNIKeyExpr?, keyExprString: String, parameters: String?, callback: JNIGetCallback, onClose: JNIOnCloseCallback, attachmentBytes: ByteArray?, payload: ByteArray?, encodingId: Int, encodingSchema: String?)
```

### JNIKeyExpr (zenoh-jni-runtime)
```
tryFrom(keyExpr: String): String
autocanonize(keyExpr: String): String
intersects(a: JNIKeyExpr?, aStr: String, b: JNIKeyExpr?, bStr: String): Boolean
includes(a: JNIKeyExpr?, aStr: String, b: JNIKeyExpr?, bStr: String): Boolean
relationTo(a: JNIKeyExpr?, aStr: String, b: JNIKeyExpr?, bStr: String): Int
join(a: JNIKeyExpr?, aStr: String, other: String): String
concat(a: JNIKeyExpr?, aStr: String, other: String): String
// NOTE: method names are join/concat (NOT joinViaJNI/concatViaJNI)
```

### JNIZBytes (zenoh-jni-runtime)
Present at `io.zenoh.jni.JNIZBytes` — `@PublishedApi internal object`. Zenoh-kotlin's local copy must be deleted.

### JNILogger (zenoh-jni-runtime)
Present at `io.zenoh.jni.JNILogger` — `public object` with `startLogs(filter: String)`.

### ZenohLoad / Target / ZError (zenoh-jni-runtime)
- `public expect object ZenohLoad` (commonMain) + JVM and Android actuals provided
- `public enum class Target` (jvmMain)
- `class ZError` in `io.zenoh.exceptions` (commonMain)

---

## Phase 1: Add zenoh-java as Git Submodule

Add `https://github.com/eclipse-zenoh/zenoh-java.git` as a submodule at path `zenoh-java/` in the zenoh-kotlin root, pinned to commit `c4ec1d89c246a76edd03128593fd34f6641c405d` (PR 465 HEAD).

```
git submodule add https://github.com/eclipse-zenoh/zenoh-java.git zenoh-java
git -C zenoh-java checkout c4ec1d89c246a76edd03128593fd34f6641c405d
```

Commit `.gitmodules` and the submodule entry. The native Rust crate and `zenoh-jni-runtime` are then available at `zenoh-java/zenoh-jni/` and `zenoh-java/zenoh-jni-runtime/` respectively.

---

## Phase 2: Gradle Build Configuration

### 2a. `settings.gradle.kts` (root)

- Remove `include(":zenoh-jni")`
- Add `includeBuild("zenoh-java")` with dependency substitution, **conditioned on non-remote publication**:

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

When `remotePublication=true` (set by publish CI), the `includeBuild` is skipped and `zenoh-jni-runtime` is resolved from Maven Central (where zenoh-java's pipeline publishes it before zenoh-kotlin).

### 2b. Root `build.gradle.kts`

- Remove `classpath("org.mozilla.rust-android-gradle:plugin:0.9.6")` from `buildscript.dependencies`
- Remove `id("org.mozilla.rust-android-gradle.rust-android") version "0.9.6" apply false` from `plugins`

### 2c. `zenoh-kotlin/build.gradle.kts`

**Remove:**
- The `buildZenohJni` task and `buildZenohJNI` helper function, `BuildMode` enum
- The `configureAndroid()` Cargo plugin portion and `configureCargo()` function (keep the pure `android {}` configuration block: namespace, compileSdk, minSdk, etc.)
- `org.mozilla.rust-android-gradle.rust-android` plugin application
- `tasks.whenObjectAdded { ... cargoBuild ... }` block
- `jvmMain` resource `srcDir` pointing to `../zenoh-jni/target/...`
- `jvmTest` resource `srcDir` pointing to `../zenoh-jni/target/...`
- `tasks.withType<Test> { systemProperty("java.library.path", ...) }` — `ZenohLoad` in zenoh-jni-runtime handles native library loading from its own classpath resources

**Add:**
- `zenoh-jni-runtime` as `api` dependency in `commonMain` (coordinates: `org.eclipse.zenoh:zenoh-jni-runtime`)
- Task wiring to trigger the native build from the included build before JVM compilation:

```kotlin
tasks.named("compileKotlinJvm") {
    dependsOn(gradle.includedBuild("zenoh-java").task(":zenoh-jni-runtime:buildZenohJni"))
}
```

Note: This task wiring uses Gradle's included build API (`gradle.includedBuild(...).task(...)`) which is the correct way to reference tasks in composite builds. This dependency is only registered when `isRemotePublication` is false (since the includeBuild itself is only added then). Wrap the `dependsOn` in an `if (!isRemotePublication)` guard to avoid failing when the included build is not present.

### 2d. `examples/build.gradle.kts`

- Replace the `CompileZenohJNI` task (which ran `cargo build --release --manifest-path ../zenoh-jni/Cargo.toml`) with a dependency on the included build's task:

```kotlin
tasks.register("CompileZenohJNI") {
    dependsOn(gradle.includedBuild("zenoh-java").task(":zenoh-jni-runtime:buildZenohJni"))
}
```

- Update `java.library.path` in each `JavaExec` task from `../zenoh-jni/target/release` to `../zenoh-java/zenoh-jni/target/release`

---

## Phase 3: Delete All Local JNI Wrapper Files

### 3a. Delete all files in `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/`

Delete ALL files including `JNIZBytes.kt` (it IS in zenoh-jni-runtime).

Files to delete:
- `JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt`, `JNIConfig.kt`, `JNIKeyExpr.kt`, `JNILiveliness.kt`, `JNILivelinessToken.kt`, `JNIMatchingListener.kt`, `JNIPublisher.kt`, `JNIQuerier.kt`, `JNIQueryable.kt`, `JNIQuery.kt`, `JNISampleMissListener.kt`, `JNIScout.kt`, `JNISession.kt`, `JNISubscriber.kt`, `JNIZBytes.kt`, `JNIZenohId.kt`
- Entire `callbacks/` subdirectory

### 3b. Delete duplicate shared classes (now provided by zenoh-jni-runtime)

- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (the ZenohLoad JVM actual)
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt`
- `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` (ZenohLoad Android actual)

### 3c. Update `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt`

Remove the `internal expect object ZenohLoad` declaration at the bottom. The `public ZenohLoad` from zenoh-jni-runtime replaces it. All usages of `ZenohLoad` in `scout()` and `tryInitLogFromEnv()` remain as-is (they now resolve to the runtime's `ZenohLoad`).

---

## Phase 4: Migrate `Config.kt`

Map all calls to the old internal `JNIConfig` to the runtime's public `JNIConfig`. Changes to `Config.kt` (the facade class):

| Old call | New call |
|----------|----------|
| `JNIConfig.loadDefaultConfig()` → returns `Config` | `Config(JNIConfig.loadDefault())` |
| `JNIConfig.loadConfigFile(path)` → returns `Result<Config>` | `runCatching { Config(JNIConfig.loadFromFile(path.toString())) }` |
| `JNIConfig.loadJsonConfig(raw)` | `runCatching { Config(JNIConfig.loadFromJson(raw)) }` |
| `JNIConfig.loadJson5Config(raw)` | `runCatching { Config(JNIConfig.loadFromJson(raw)) }` — no json5 method in runtime; identical to json (this is what zenoh-java does) |
| `JNIConfig.loadYamlConfig(raw)` | `runCatching { Config(JNIConfig.loadFromYaml(raw)) }` |
| `jniConfig.getJson(key)` (returned `Result<String>`) | `runCatching { jniConfig.getJson(key) }` — runtime throws ZError |
| `jniConfig.insertJson5(key, value)` (returned `Result<Unit>`) | `runCatching { jniConfig.insertJson5(key, value) }` — runtime throws ZError |

The `Config` class stores `internal val jniConfig: JNIConfig` — the type is unchanged but now resolves to the runtime's public `JNIConfig`.

---

## Phase 5: Migrate `Session.kt`

### Session open

Old internal JNISession had:
```kotlin
internal class JNISession {
    internal var sessionPtr: AtomicLong = AtomicLong(0)
    fun open(config: Config): Result<Unit>
}
```

New runtime JNISession:
```kotlin
public class JNISession(val sessionPtr: Long)
companion: open(config: JNIConfig): JNISession
```

Changes in `Session.kt`:
- Old: `jniSession = JNISession(); jniSession?.open(config)?.getOrThrow()` → New: `jniSession = JNISession.open(config.jniConfig)`
- `internal var jniSession: JNISession?` now resolves to runtime's public class
- All occurrences of `jniSession.sessionPtr.get()` → `jniSession.sessionPtr` (plain Long)

For every operation in Session.kt that previously called `jniSession.declarePublisher(...)` etc. with domain objects, the pattern is now calling the runtime's JNISession directly with primitives extracted inline. Reference the zenoh-java PR's Session.kt for the exact primitive extraction and callback assembly patterns.

---

## Phase 6: Migrate `KeyExpr.kt`

The runtime's `JNIKeyExpr` companion methods have different signatures. Update all calls in `KeyExpr.kt`:

| Old | New |
|-----|-----|
| `JNIKeyExpr.intersects(this, other)` | `JNIKeyExpr.intersects(jniKeyExpr, keyExpr, other.jniKeyExpr, other.keyExpr)` |
| `JNIKeyExpr.includes(this, other)` | `JNIKeyExpr.includes(jniKeyExpr, keyExpr, other.jniKeyExpr, other.keyExpr)` |
| `JNIKeyExpr.relationTo(this, other)` | `JNIKeyExpr.relationTo(jniKeyExpr, keyExpr, other.jniKeyExpr, other.keyExpr)` |
| `JNIKeyExpr.joinViaJNI(this, other)` | `JNIKeyExpr.join(jniKeyExpr, keyExpr, other)` |
| `JNIKeyExpr.concatViaJNI(this, other)` | `JNIKeyExpr.concat(jniKeyExpr, keyExpr, other)` |

The field `internal var jniKeyExpr: JNIKeyExpr?` now resolves to the runtime's public class.

---

## Phase 7: Migrate `Liveliness.kt`

Replace all `JNILiveliness.*` calls with inline calls on the runtime's `JNISession`. The callback assembly logic that was in the old `JNILiveliness` object moves into `Liveliness.kt` itself.

Mapping:
- `JNILiveliness.declareToken(jniSession, keyExpr)` → `LivelinessToken(jniSession.declareLivelinessToken(keyExpr.jniKeyExpr, keyExpr.keyExpr))`
- `JNILiveliness.get(jniSession, keyExpr, callback, receiver, timeout, onClose)` → inline `JNIGetCallback` assembly, then `jniSession.livelinessGet(keyExpr.jniKeyExpr, keyExpr.keyExpr, getCallback, timeout.toMillis(), onClose)`
- `JNILiveliness.declareSubscriber(jniSession, keyExpr, callback, receiver, history, onClose)` → inline `JNISubscriberCallback` assembly, then `jniSession.declareLivelinessSubscriber(keyExpr.jniKeyExpr, keyExpr.keyExpr, subCallback, history, onClose)`

Reference zenoh-java's `Liveliness.kt` in the PR branch for the exact callback assembly pattern.

---

## Phase 8: Migrate Domain Classes — Publisher, AdvancedPublisher, AdvancedSubscriber, Query, Querier

The old internal JNI adapter classes wrapped domain objects and converted them to primitives internally. After deleting those classes, the domain-level classes must inline the primitive extraction before calling the runtime JNI classes.

### `Publisher.kt`
- `jniPublisher.put(payload, encoding, attachment)` → extract primitives: `jniPublisher.put(resolvedPayload.bytes, resolvedEncoding.id, resolvedEncoding.schema, attachment?.into()?.bytes)`
- `jniPublisher.delete(attachment)` → `jniPublisher.delete(attachment?.into()?.bytes)`

### `AdvancedPublisher.kt`
- Same primitive extraction pattern for `put`/`delete` as Publisher
- `jniPublisher.declareMatchingListener(callback, resolvedOnClose)` → must build `JNIMatchingListenerCallback { matching -> callback.run(matching) }` inline, then call `jniPublisher.declareMatchingListener(matchingListenerCallback, resolvedOnClose)`
- Same pattern for `declareBackgroundMatchingListener`

### `AdvancedSubscriber.kt`
- `jniSubscriber.declareDetectPublishersSubscriber(keyExpr, history, callback, onClose, receiver)` → inline `JNISubscriberCallback` assembly, then call `jniSubscriber.declareDetectPublishersSubscriber(history, subCallback, resolvedOnClose)`
- `jniSubscriber.declareSampleMissListener(callback, onClose)` → inline `JNISampleMissListenerCallback` assembly, then call `jniSubscriber.declareSampleMissListener(sampleMissCallback, resolvedOnClose)`

### `Query.kt`
- `jniQuery.replySuccess(sample)` → extract `sample.keyExpr.jniKeyExpr`, `sample.keyExpr.keyExpr`, `sample.payload.bytes`, `sample.encoding.id`, `sample.encoding.schema`, timestamp info, `attachment?.bytes`, `qos.express`; call `jniQuery.replySuccess(jniKeyExpr, keyExprString, payload, encodingId, encodingSchema, timestampEnabled, timestampNtp64, attachment, qosExpress)`
- `jniQuery.replyError(error, encoding)` → `jniQuery.replyError(error.into().bytes, encoding.id, encoding.schema)`
- `jniQuery.replyDelete(keyExpr, timestamp, attachment, qos)` → extract primitives, call `jniQuery.replyDelete(keyExpr.jniKeyExpr, keyExpr.keyExpr, timestampEnabled, timestampNtp64, attachment?.bytes, qos.express)`

### `Querier.kt`
- Inline `JNIGetCallback` assembly (currently in old `JNIQuerier.kt`)
- Call `jniQuerier.get(keyExpr.jniKeyExpr, keyExpr.keyExpr, parameters, callback, onClose, attachmentBytes, payload, encodingId, encodingSchema)`

---

## Phase 9: Migrate `Logger.kt`

Replace the `external fun startLogsViaJNI(filter: String)` with a delegation to the runtime's `JNILogger`:

```kotlin
fun start(filter: String) = runCatching {
    JNILogger.startLogs(filter)
}
```

Remove the `@Throws(ZError::class) private external fun startLogsViaJNI(filter: String)` declaration.

---

## Phase 10: Delete Rust Code

- Delete entire `zenoh-jni/` directory (the Rust crate)
- Delete `rust-toolchain.toml` from the zenoh-kotlin root

---

## Phase 11: Update CI Workflows

### `.github/workflows/ci.yml`
- Add `submodules: recursive` to all `actions/checkout` steps
- Remove Rust-specific steps: `Cargo Format`, `Clippy Check`, `Check for feature leaks`, any direct `cargo build` targeting `zenoh-jni/`
- Keep any `Install Rust toolchain` step that is needed, as the submodule's `buildZenohJni` Gradle task will invoke `cargo` internally

### `.github/workflows/publish-jvm.yml`
- Add `submodules: recursive` to checkout step
- Remove cross-compilation matrix jobs and `cargo`/`cross build` steps that built `zenoh-kotlin`'s old `zenoh-jni/` and collected `jni-libs/`
- Keep `./gradlew publishJvmPublicationToSonatypeRepository -PremotePublication=true`; with `remotePublication=true`, the `includeBuild` substitution is skipped and `zenoh-jni-runtime` is resolved from Maven Central

### `.github/workflows/publish-android.yml`
- Add `submodules: recursive` to checkout step
- Remove `cargo build` steps targeting `zenoh-kotlin`'s own `zenoh-jni/`
- Gradle task dependency on `zenoh-jni-runtime` (via the Android cargo plugin in the included build) handles native Android build

---

## Publication Strategy (explicit)

- **Local development / CI test**: `includeBuild("zenoh-java")` is active (submodule present, `remotePublication` not set). `compileKotlinJvm` depends on `:zenoh-jni-runtime:buildZenohJni` in the included build. Gradle builds the Rust crate from `zenoh-java/zenoh-jni/`. Zenoh-kotlin resolves `zenoh-jni-runtime` as a project dependency from the composite build.

- **Maven Central publication**: The zenoh-java pipeline must publish `org.eclipse.zenoh:zenoh-jni-runtime` to Maven Central **before** zenoh-kotlin's publication run. Then zenoh-kotlin's workflow sets `remotePublication=true`: the `includeBuild` is skipped, `zenoh-jni-runtime` is resolved from Maven Central. Zenoh-kotlin publishes only its own Kotlin facade code with a transitive dependency on the already-published runtime. **This means the zenoh-kotlin publication CI must be ordered after the zenoh-java publication CI in any joint release process.**

---

## File Change Summary

| Action | Files/Paths |
|--------|-------------|
| **Add** | `.gitmodules`, `zenoh-java/` (submodule) |
| **Delete** | `zenoh-jni/` (entire Rust crate), `rust-toolchain.toml`, ALL of `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/` (including JNIZBytes.kt), ALL of `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/`, `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`, `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt`, `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt`, `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` |
| **Modify** | `settings.gradle.kts`, `build.gradle.kts` (root), `zenoh-kotlin/build.gradle.kts`, `examples/build.gradle.kts`, `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt`, `Config.kt`, `Session.kt`, `KeyExpr.kt`, `Liveliness.kt`, `Logger.kt`, `Publisher.kt`, `AdvancedPublisher.kt`, `AdvancedSubscriber.kt`, `Query.kt`, `Querier.kt`, `.github/workflows/ci.yml`, `.github/workflows/publish-jvm.yml`, `.github/workflows/publish-android.yml` |

---

## Verification Steps

1. `./gradlew :zenoh-kotlin:compileKotlinJvm` — should trigger `:zenoh-jni-runtime:buildZenohJni` from the included build and compile without missing class errors
2. `./gradlew :zenoh-kotlin:jvmTest` — all tests pass; native library loaded by zenoh-jni-runtime's ZenohLoad
3. `./gradlew :examples:ZPub` — runs with updated `java.library.path` pointing to `../zenoh-java/zenoh-jni/target/release`
4. Verify ZBytes serialization/deserialization still works (tests using JNIZBytes from the runtime)
5. `grep -r "zenoh-jni" settings.gradle.kts build.gradle.kts zenoh-kotlin/build.gradle.kts` — should show only `zenoh-java/zenoh-jni` (submodule path) and `zenoh-jni-runtime` (module name), never `include(":zenoh-jni")`
6. No `external fun` declarations remain in zenoh-kotlin's own Kotlin source (all external calls go through runtime classes)

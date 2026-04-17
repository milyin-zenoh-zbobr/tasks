# Implementation Plan: Make zenoh-kotlin Use zenoh-jni-runtime from zenoh-java

## Rationale and Design Decisions

The PR https://github.com/eclipse-zenoh/zenoh-java/pull/465 (branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`, head SHA `c4ec1d89`) introduces `zenoh-jni-runtime` — a Kotlin multiplatform module in zenoh-java that exposes **public, primitive-only** JNI adapters. Currently, both zenoh-java and zenoh-kotlin maintain separate, near-identical JNI Kotlin wrapper classes. The goal is to have zenoh-kotlin consume zenoh-jni-runtime from zenoh-java instead.

**Key API difference:** zenoh-kotlin's current JNI classes are `internal` and accept Kotlin domain objects (KeyExpr, QoS, Encoding, etc.), handling the conversion to primitives internally. zenoh-jni-runtime's classes are `public` and accept only primitives (ByteArray, Int, Long, String). This means zenoh-kotlin's domain classes (Session.kt, Publisher.kt, etc.) must inline the conversion logic that was previously inside the JNI classes.

**Closest analog:** zenoh-java's own refactoring in the same PR. Session.kt, Publisher.kt, etc. in zenoh-java were updated to call primitive JNI adapters directly. zenoh-kotlin should follow the same pattern, adapted for Kotlin idioms (Result types, extension functions, etc.).

**Build strategy:** Add zenoh-java as a **git submodule** and use a **Gradle composite build** (`includeBuild`). This eliminates the need for zenoh-kotlin to maintain its own Rust code (native `libzenoh_jni`) — that comes from zenoh-java's `zenoh-jni` Rust crate.

---

## Phase 1: Add zenoh-java as a Git Submodule

1. Add zenoh-java as a submodule, locked to the PR branch SHA (`c4ec1d89c246a76edd03128593fd34f6641c405d`):
   ```
   git submodule add https://github.com/eclipse-zenoh/zenoh-java.git zenoh-java
   git -C zenoh-java checkout c4ec1d89c246a76edd03128593fd34f6641c405d
   ```
2. Commit `.gitmodules` and the `zenoh-java` directory reference.

This gives zenoh-kotlin access to both `zenoh-jni` (Rust) and `zenoh-jni-runtime` (Kotlin) from zenoh-java.

---

## Phase 2: Gradle Build Configuration

### 2a. `settings.gradle.kts` (root)
- Add `includeBuild("zenoh-java")` with dependency substitution, so `org.eclipse.zenoh:zenoh-jni-runtime` is resolved from the local submodule:
  ```kotlin
  includeBuild("zenoh-java") {
      dependencySubstitution {
          substitute(module("org.eclipse.zenoh:zenoh-jni-runtime")).using(project(":zenoh-jni-runtime"))
      }
  }
  ```
- Remove `include(":zenoh-jni")` (the local Rust subproject).

### 2b. `zenoh-kotlin/build.gradle.kts`
- Remove all Cargo/Rust build logic: the `buildZenohJni` task, `BuildMode` enum, `configureAndroid`/`configureCargo` functions, and `tasks.named("compileKotlinJvm") { dependsOn("buildZenohJni") }`.
- Remove native library resource directories that point to the local `../zenoh-jni/target/` (both `jvmMain` and `jvmTest`).
- For the non-remote-publication case, point resources to the zenoh-java submodule's native output: `../zenoh-java/zenoh-jni/target/$buildMode`.
- Add zenoh-jni-runtime as a dependency (it transitively brings the native library resources at publish time):
  ```kotlin
  val commonMain by getting {
      dependencies {
          api("org.eclipse.zenoh:zenoh-jni-runtime:${version}")
          // ... existing dependencies
      }
  }
  ```
- Update `tasks.withType<Test>` to reference `../zenoh-java/zenoh-jni/target/$buildMode` for `java.library.path`.
- Add `tasks.named("compileKotlinJvm") { dependsOn(":zenoh-jni-runtime:buildZenohJni") }` so the native library is built before compilation.
- Remove the Android Cargo plugin configuration (now in zenoh-jni-runtime).

### 2c. Root `build.gradle.kts`
- Remove `classpath("org.mozilla.rust-android-gradle:plugin:0.9.6")` and `id("org.mozilla.rust-android-gradle.rust-android")` from buildscript/plugins since Android Rust build is handled by zenoh-jni-runtime.

---

## Phase 3: Remove zenoh-kotlin's Own JNI Kotlin Classes

Delete the entire `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/` directory and all files within it. These are now provided by zenoh-jni-runtime:
- `JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt`, `JNIConfig.kt`, `JNIKeyExpr.kt`
- `JNILiveliness.kt` (merged into `JNISession` in zenoh-jni-runtime)
- `JNILivelinessToken.kt`, `JNIMatchingListener.kt`, `JNIPublisher.kt`, `JNIQuerier.kt`
- `JNIQueryable.kt`, `JNIQuery.kt`, `JNISampleMissListener.kt`, `JNIScout.kt`
- `JNISession.kt`, `JNISubscriber.kt`, `JNIZBytes.kt`, `JNIZenohId.kt`
- `callbacks/` subdirectory (all callback interfaces: `JNIGetCallback`, `JNIMatchingListenerCallback`, `JNIOnCloseCallback`, `JNIQueryableCallback`, `JNISampleMissListenerCallback`, `JNIScoutCallback`, `JNISubscriberCallback`)

Delete ZenohLoad and Target classes (provided by zenoh-jni-runtime):
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (ZenohLoad JVM actual)
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt`
- `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` (ZenohLoad Android actual)

---

## Phase 4: Update `Zenoh.kt` (commonMain)

In `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt`:
- Remove the `internal expect object ZenohLoad` declaration at the bottom — it is now `public expect object ZenohLoad` in zenoh-jni-runtime.
- The `ZenohLoad` usages in this file (e.g., `ZenohLoad` in `scout()` and `tryInitLogFromEnv()`) remain as-is — they reference zenoh-jni-runtime's `ZenohLoad`.
- Update `scout()` methods to inline the `JNIScoutCallback` assembly (previously in `JNIScout.companion.scout()`). Create the callback that converts primitive parameters (`whatAmI2: Int, id: ByteArray, locators: List<String>`) to `Hello`, then call `JNIScout.scout(whatAmI = binaryWhatAmI, callback = scoutCallback, onClose = ..., config = config?.jniConfig)`.

---

## Phase 5: Refactor `Config.kt`

`Config.kt` references the deleted `internal JNIConfig`. Update:
- Replace calls to `JNIConfig.loadDefaultConfig()` → `JNIConfig.loadDefault()`
- Replace calls to `JNIConfig.loadConfigFile(path)` → `JNIConfig.loadFromFile(path.toString())`
- Replace calls to `JNIConfig.loadJsonConfig(raw)` → `JNIConfig.loadFromJson(raw)`
- Replace calls to `JNIConfig.loadYamlConfig(raw)` → `JNIConfig.loadFromYaml(raw)`
- The `jniConfig: JNIConfig` internal field on Config stays — just now it holds the public `JNIConfig` from zenoh-jni-runtime.
- Update `getJson()` and `insertJson5()` delegates to use the public methods `jniConfig.getJson(key)` and `jniConfig.insertJson5(key, value)` (now non-Result, throwing `ZError`). Wrap in `runCatching` in Config.kt.

---

## Phase 6: Refactor `Session.kt`

This is the largest change. `Session.kt` currently delegates to a "fat" `JNISession` (552 lines) that handles callback assembly and primitive conversion. That logic must be inlined into `Session.kt`, calling the "thin" `JNISession` from zenoh-jni-runtime.

For each operation currently done via `jniSession?.run { someHighLevelMethod(...) }`, replace with direct primitive JNI calls:

**Session open/close:**
- `launch()`: Change `jniSession = JNISession(); jniSession!!.open(config)` to `jniSession = JNISession.open(config.jniConfig)`.
- `close()`: Change `jniSession?.close()` to `jniSession?.close()` (same, but now JNISession.close() is the public primitive method).
- The field `internal var jniSession: JNISession?` remains but now holds zenoh-jni-runtime's JNISession.

**declarePublisher:** Inline from `JNISession.declarePublisher()`. Call `jniSession.declarePublisher(keyExpr.jniKeyExpr, keyExpr.keyExpr, qos.congestionControl.value, qos.priority.value, qos.express, reliability.value)` and create `Publisher(keyExpr, qos, encoding, JNIPublisher(result))`.

**declareSubscriber:** Inline callback assembly from `JNISession.declareSubscriber()`. Create `JNISubscriberCallback { keyExpr2, payload, encodingId, schema, kind, timestamp64, timestampIsValid, attachment, express, priority, congestionControl -> ... }` converting to `Sample`, then call `jniSession.declareSubscriber(keyExpr.jniKeyExpr, keyExpr.keyExpr, callback, onClose)`.

**declareQueryable:** Inline `JNIQueryableCallback` assembly. Call `jniSession.declareQueryable(...)`.

**declareQuerier:** Inline from `JNISession.declareQuerier()`. Pass all qos/timeout/target as primitives.

**performGet / get:** Inline `JNIGetCallback` assembly (converts Reply parameters), call `jniSession.get(jniKeyExpr, keyExprString, params, callback, onClose, timeoutMs, target, consolidation, attachmentBytes, payload, encodingId, schema, congestionControl, priority, express, acceptReplies)`.

**performPut / put:** Call `jniSession.put(jniKeyExpr, keyExprString, valuePayload, valueEncoding, schema, congestionControl, priority, express, attachment, reliability)` with primitives.

**performDelete / delete:** Call `jniSession.delete(...)` with primitives.

**declareKeyExpr / undeclareKeyExpr:** Call `jniSession.declareKeyExpr(keyExpr.keyExpr)` and `jniSession.undeclareKeyExpr(jniKeyExpr)`.

**zid / peersZid / routersZid:** Call `jniSession.getZid()`, `jniSession.getPeersZid()`, `jniSession.getRoutersZid()` and convert `ByteArray` to `ZenohId`.

**declareAdvancedPublisher:** Inline from `JNISession.declareAdvancedPublisher()`. Pass all config fields as primitives.

**declareAdvancedSubscriber:** Inline callback assembly. Pass all history/recovery config fields as primitives.

**Liveliness operations** (previously in `JNILiveliness`): All three liveliness operations are now on `JNISession` in zenoh-jni-runtime:
- `liveliness.get()` → `jniSession.livelinessGet(...)` 
- `liveliness.declareToken()` → `jniSession.declareLivelinessToken(...)`
- `liveliness.declareSubscriber()` → `jniSession.declareLivelinessSubscriber(...)`

These are called from `Liveliness.kt` which holds a reference to the `Session`; update accordingly.

---

## Phase 7: Update Domain Classes

### `Publisher.kt`
- Change `jniPublisher?.put(payload, encoding, attachment)` → `jniPublisher?.put(resolvedPayload.bytes, resolvedEncoding.id, resolvedEncoding.schema, attachment?.into()?.bytes)`.
- Change `jniPublisher?.delete(attachment)` → `jniPublisher?.delete(attachment?.into()?.bytes)`.
- The `JNIPublisher` field type stays the same name, now from zenoh-jni-runtime.

### `AdvancedPublisher.kt`
- Same pattern as Publisher: convert domain objects to primitives before calling `jniAdvancedPublisher.put(...)` and `delete(...)`.
- For matching listener operations: inline `JNIMatchingListenerCallback` assembly (convert `Boolean` status to `MatchingStatus`), then call `jniAdvancedPublisher.declareMatchingListener(callback, onClose)`.

### `AdvancedSubscriber.kt`
- Inline `JNISubscriberCallback` assembly for `declareDetectPublishersSubscriber`.
- Inline `JNISampleMissListenerCallback` assembly for `declareSampleMissListener`.

### `MatchingListener.kt`
- The `JNIMatchingListener` class in zenoh-jni-runtime has a `close()` method; ensure `jniMatchingListener?.close()` works.

### `SampleMissListener.kt`
- Same: `JNISampleMissListener` is now from zenoh-jni-runtime; just need close.

### `Query.kt`
- Change `jniQuery?.replySuccess(keyExpr, payload, encoding, timestamp, attachment, qosExpress)` → call with primitives: `jniQuery?.replySuccess(jniKeyExpr, keyExprString, payload.bytes, encodingId, encodingSchema, timestampEnabled, timestampNtp64, attachment?.bytes, qosExpress)`.
- Same for `replyError` and `replyDelete`.

### `Querier.kt`
- Change `jniQuerier?.get(keyExpr, params, callback, onClose, attachment, payload, encoding)` → inline `JNIGetCallback` assembly and call `jniQuerier?.get(jniKeyExpr, keyExprString, parameters, primitiveCallback, onClose, attachmentBytes, payloadBytes, encodingId, schema)`.

### `Queryable.kt`
- Just holds `JNIQueryable?`; the class from zenoh-jni-runtime has the same `close()` method. Change field type to reference zenoh-jni-runtime's public class (no internal restriction).

### `Subscriber.kt`
- Just holds `JNISubscriber?`; same `close()` method. Update reference.

### `LivelinessToken.kt`
- Holds `JNILivelinessToken?`; the class has `close()` method in zenoh-jni-runtime. Update reference.

### `Scout.kt`
- Holds `JNIScout?`; `JNIScout.close()` exists in zenoh-jni-runtime. No functional change.

### `KeyExpr.kt`
- `KeyExpr` holds an `internal var jniKeyExpr: JNIKeyExpr?`. The `JNIKeyExpr` is now from zenoh-jni-runtime (public class). Same functionality.
- The `close()` and `autocancel()` that call `jniKeyExpr.close()` remain.

### `Logger.kt`
- Change `Logger.startLogsViaJNI(filter)` → `JNILogger.startLogs(filter)`. 
- `Logger.start(filter)` in commonMain can delegate to `JNILogger.startLogs(filter)`.

### `config/ZenohId.kt`
- `ZenohId` holds a `ByteArray`. The `JNIZenohId` class in zenoh-jni-runtime provides encoding/parsing; if used, update to use public API.

---

## Phase 8: Remove Rust Code

1. Delete the entire `zenoh-jni/` directory (Cargo.toml, src/, Cargo.lock).
2. Delete `rust-toolchain.toml` from zenoh-kotlin root (the Rust toolchain is now managed in zenoh-java).

---

## Phase 9: Update CI Workflows

### `.github/workflows/ci.yml`
- Remove steps: `Cargo Format`, `Clippy Check`, `Check for feature leaks`, `Build Zenoh-JNI` that work in `zenoh-jni/`.
- Add step: `git submodule update --init --recursive` after checkout.
- The Rust build will happen automatically via `buildZenohJni` Gradle task (delegated to `:zenoh-jni-runtime:buildZenohJni`).

### `.github/workflows/publish-jvm.yml`
- Add submodule initialization step.
- Update Rust build steps to use `zenoh-java/zenoh-jni` directory.
- Update `JNI_LIB_PATHS` references if needed.

---

## Phase 10: Verification

1. Run `./gradlew :zenoh-kotlin:jvmTest` to verify all tests pass.
2. Verify that Rust code is no longer compiled as part of the zenoh-kotlin build.
3. Verify that a local `./gradlew :zenoh-kotlin:compileKotlinJvm` triggers the native build via zenoh-jni-runtime.

---

## File Change Summary

| Action | Files |
|--------|-------|
| **Add** | `.gitmodules`, `zenoh-java/` (submodule) |
| **Delete** | `zenoh-jni/` (entire Rust crate), `rust-toolchain.toml`, all files in `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/`, `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt`, `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt`, `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` |
| **Modify** | `settings.gradle.kts`, `build.gradle.kts`, `zenoh-kotlin/build.gradle.kts`, `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt`, `Config.kt`, `Session.kt`, `Publisher.kt`, `AdvancedPublisher.kt`, `AdvancedSubscriber.kt`, `Query.kt`, `Querier.kt`, `Logger.kt`, `Liveliness.kt`, `Scout.kt`, `KeyExpr.kt`, CI workflows |

---

## Important Notes for Implementation

- **zenoh-kotlin's Session.kt is ~1200 lines** vs zenoh-java's Session.kt at ~900 lines after refactoring. This is because zenoh-kotlin has Kotlin-specific patterns (Result types, extension functions, coroutines). The inlined callback assembly will add ~300 lines to Session.kt.
- **JNILiveliness is gone**: Liveliness operations must use `JNISession` methods directly (`livelinessGet`, `declareLivelinessToken`, `declareLivelinessSubscriber`). `Liveliness.kt` calls these via the `Session`'s `jniSession`.
- **Package: `io.zenoh.jni` is preserved**: All imports in zenoh-kotlin still use `io.zenoh.jni.JNIXxx` — these now resolve to zenoh-jni-runtime's classes. No package rename needed.
- **ZError**: zenoh-jni-runtime defines `io.zenoh.exceptions.ZError` — this is the same package as zenoh-kotlin's existing `ZError`. Verify no conflict (both should be identical since they're the same class from zenoh-jni-runtime).
- **`exceptions/ZError.kt` in zenoh-kotlin**: If zenoh-kotlin defines its own `ZError`, it should be deleted since zenoh-jni-runtime defines the same class. Verify that zenoh-kotlin's `ZError` and zenoh-jni-runtime's `ZError` are identical or consolidate.

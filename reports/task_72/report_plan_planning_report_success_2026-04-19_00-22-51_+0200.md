# Implementation Plan v5: Make zenoh-kotlin Depend on zenoh-jni-runtime

## Compatibility Assessment (Planner-Verified)

**zenoh-jni-runtime IS sufficient as a replacement for zenoh-kotlin's JNI layer.** It covers all operations: session, publisher, subscriber, querier, queryable, key expressions, scouting, liveliness, serialization, and logging.

**HOWEVER, zenoh-jni-runtime is NOT a drop-in API replacement.** The runtime's JNI classes share package/class names (`io.zenoh.jni.*`) with zenoh-kotlin's own JNI adapters, but their Kotlin-facing method signatures are different: the runtime uses primitive types (`ByteArray`, `Int`, `String?`) everywhere, while zenoh-kotlin's own JNI adapters accepted domain objects (`IntoZBytes`, `Encoding`, `KeyExpr`, `Sample`, etc.) and wrapped results in `Result<T>`. The migration must adapt call sites, not just swap imports.

---

## Key Design Decisions

1. **Class name conflict**: Both codebases define `io.zenoh.jni.JNISession`, `JNIPublisher`, etc. They cannot coexist. Strategy: delete ALL zenoh-kotlin's JNI classes; domain classes hold the runtime's versions directly.

2. **Adaptation strategy**: Follow zenoh-java's approach exactly — the domain classes (`Session.kt`, `Publisher.kt`, `Config.kt`, etc.) perform the domain-object → primitive conversion inline before calling runtime JNI methods. The primary reference is `zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt` and its sibling files on the `common-jni` branch.

3. **Serialization source-set mismatch**: `ZSerialize.kt`/`ZDeserialize.kt` must remain in `commonMain` (public API constraint). Runtime's `JNIZBytesKotlin` lives in `jvmAndAndroidMain`. Solution: add an internal `expect/actual` bridge in zenoh-kotlin (`ZBytesJNIBridge.kt`) with `commonMain` expect declarations and `jvmMain`/`androidMain` actuals.

4. **ZenohLoad**: Delete zenoh-kotlin's own `expect object ZenohLoad` and its `actual` implementations; use the runtime's `io.zenoh.ZenohLoad` directly.

5. **Composite build gating**: Gate `includeBuild("zenoh-java")` behind `file("zenoh-java/settings.gradle.kts").exists()` so clones without submodule init resolve from Maven Central.

---

## Phase 0: Add zenoh-java as Git Submodule

```
git submodule add -b common-jni https://github.com/eclipse-zenoh/zenoh-java.git zenoh-java
```

Creates `.gitmodules`.

---

## Phase 1: Update Gradle Build Configuration

### `settings.gradle.kts` (root)
- Remove `:zenoh-jni` from `include()`.
- Add gated composite build substitution:
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

### Root `build.gradle.kts`
- Remove `org.mozilla.rust-android-gradle:plugin` from buildscript dependencies.

### `zenoh-kotlin/build.gradle.kts`
- **Add dependency**:
  ```kotlin
  commonMain.dependencies {
      implementation("org.eclipse.zenoh:zenoh-jni-runtime:<version>")
  }
  ```
  Where `<version>` matches `version.txt`.

- **Remove**:
  - `buildZenohJni` task, `buildZenohJNI()` function, all Cargo/NDK task wiring
  - `compileKotlinJvm.dependsOn("buildZenohJni")`
  - `tasks.whenObjectAdded { ... cargoBuild ... }` block
  - `tasks.withType<Test>` block setting `java.library.path` to Rust target dir
  - The `isRemotePublication`-gated `jvmMain` resource source dirs for `../jni-libs` and `../zenoh-jni/target` (keep the signing gate itself)

---

## Phase 2: Serialization Source-Set Bridge (Preserves `commonMain` Public API)

**Problem**: `ZSerialize.kt` / `ZDeserialize.kt` are in `commonMain` and import `io.zenoh.jni.JNIZBytes.serializeViaJNI` (zenoh-kotlin's own `commonMain` class). After deleting `JNIZBytes.kt`, `commonMain` cannot reach `JNIZBytesKotlin` (runtime, `jvmAndAndroidMain`).

**Solution**: Add an internal `expect/actual` bridge at `zenoh-kotlin/src/*/kotlin/io/zenoh/jni/ZBytesJNIBridge.kt`.

- **`commonMain`**: declare `@PublishedApi internal expect fun serializeViaJNI(value: Any, kType: KType): ZBytes` and `deserializeViaJNI`.
- **`jvmMain`**: actual implementations delegating to `JNIZBytesKotlin.serialize(value, kType).into()` / `JNIZBytesKotlin.deserialize(zBytes.bytes, kType)`.
- **`androidMain`**: identical to `jvmMain`.

`ZSerialize.kt` and `ZDeserialize.kt` in `commonMain` remain in place. Update their imports from `io.zenoh.jni.JNIZBytes.serializeViaJNI` to `io.zenoh.jni.serializeViaJNI` / `deserializeViaJNI` (the bridge function). The public function signatures are unchanged.

---

## Phase 3: Delete zenoh-kotlin's JNI Package and Adapt Domain Classes

### 3a. Files to delete entirely

All files under `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/`:
- `JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt`, `JNIConfig.kt`, `JNIKeyExpr.kt`
- `JNILivelinessToken.kt`, `JNILogger.kt`, `JNIMatchingListener.kt`, `JNIPublisher.kt`
- `JNIQuerier.kt`, `JNIQuery.kt`, `JNIQueryable.kt`, `JNISampleMissListener.kt`
- `JNIScout.kt`, `JNISession.kt`, `JNISubscriber.kt`, `JNIZenohId.kt`, `JNIZBytes.kt`

All files under `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/`:
- `JNIGetCallback.kt`, `JNIMatchingListenerCallback.kt`, `JNIOnCloseCallback.kt`
- `JNIQueryableCallback.kt`, `JNISampleMissListenerCallback.kt`, `JNIScoutCallback.kt`, `JNISubscriberCallback.kt`

Platform-specific ZenohLoad files:
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (only contained `internal actual object ZenohLoad`)
- `zenoh-kotlin/src/androidMain/kotlin/io/zenoh/Zenoh.kt` (same)

### 3b. `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt`
- Remove the `internal expect object ZenohLoad` declaration at the bottom (keep the `Zenoh` public object and its methods).

### 3c. Domain class adaptations — explicit call-site changes required

The following domain classes contain method calls whose signatures differ between zenoh-kotlin's deleted JNI adapters and the runtime's JNI classes. Each must be adapted, not merely re-imported.

**Reference**: Use the corresponding file in `zenoh-java/src/commonMain/kotlin/io/zenoh/` (on the `common-jni` branch) as the canonical adaptation pattern for each class.

---

#### `Session.kt` — The largest adaptation

Currently, `Session.kt` delegates to zenoh-kotlin's `JNISession.kt` which had domain-level adapter methods (e.g., `declarePublisher(keyExpr: KeyExpr, qos: QoS, ...)` returning `Result<Publisher>`). Those adapter methods no longer exist after deletion.

**Changes**:
- `jniSession` field type stays `JNISession?` (now resolves to runtime's public `JNISession`).
- Session initialization: change `jniSession = JNISession()` then `jniSession!!.open(config)` to `jniSession = JNISession.open(config.jniConfig)`.
- Each `jniSession?.run { adapterMethod(domainObjects) }` block must be replaced with inline primitive conversion + call to the runtime's `JNISession` method. This is the same pattern that zenoh-java's `resolvePublisher`, `resolveSubscriberWithCallback`, etc. implement. Specifically:
  - Set up JNI callback lambdas inline (e.g., `JNISubscriberCallback { keyExpr1, payload, encodingId, ... -> Sample(KeyExpr(keyExpr1), payload.into(), ...) }`).
  - Call runtime methods with explicit primitives: `declarePublisher(keyExpr.jniKeyExpr, keyExpr.keyExpr, qos.congestionControl.value, qos.priority.value, qos.express, reliability.ordinal)`.
  - Wrap returned runtime JNI objects in zenoh-kotlin domain wrappers: `Publisher(keyExpr, qos, encoding, jniPublisher)`.
- The callback interfaces used in the lambdas now come from `io.zenoh.jni.callbacks.*` (runtime).
- Session close: change `jniSession?.close()` to call runtime's `JNISession.close()`.

---

#### `Config.kt` — Method name and return type change

| Old (zenoh-kotlin `JNIConfig`) | New (runtime `JNIConfig`) |
|-------------------------------|--------------------------|
| `JNIConfig.loadDefaultConfig(): Config` | `runCatching { Config(JNIConfig.loadDefault()) }` or direct `Config(JNIConfig.loadDefault())` |
| `JNIConfig.loadConfigFile(path: Path): Result<Config>` | `runCatching { Config(JNIConfig.loadFromFile(path.toString())) }` |
| `JNIConfig.loadJsonConfig(s): Result<Config>` | `runCatching { Config(JNIConfig.loadFromJson(s)) }` |
| `JNIConfig.loadJson5Config(s): Result<Config>` | `runCatching { Config(JNIConfig.loadFromJson(s)) }` (json5 parses as json) |
| `JNIConfig.loadYamlConfig(s): Result<Config>` | `runCatching { Config(JNIConfig.loadFromYaml(s)) }` |
| `jniConfig.getJson(key): Result<String>` | `runCatching { jniConfig.getJson(key) }` |
| `jniConfig.insertJson5(key, value): Result<Unit>` | `runCatching { jniConfig.insertJson5(key, value) }` |

---

#### `KeyExpr.kt` — Return type and parameter changes

| Old call | New call |
|---------|---------|
| `JNIKeyExpr.tryFrom(s): Result<KeyExpr>` | `runCatching { KeyExpr(JNIKeyExpr.tryFrom(s)) }` |
| `JNIKeyExpr.autocanonize(s): Result<KeyExpr>` | `runCatching { KeyExpr(JNIKeyExpr.autocanonize(s)) }` |
| `JNIKeyExpr.intersects(keyExprA, keyExprB)` | `JNIKeyExpr.intersects(keyExprA.jniKeyExpr, keyExprA.keyExpr, keyExprB.jniKeyExpr, keyExprB.keyExpr)` |
| `JNIKeyExpr.includes(keyExprA, keyExprB)` | `JNIKeyExpr.includes(a.jniKeyExpr, a.keyExpr, b.jniKeyExpr, b.keyExpr)` |
| `JNIKeyExpr.relationTo(ke, other): SetIntersectionLevel` | `SetIntersectionLevel.fromInt(JNIKeyExpr.relationTo(ke.jniKeyExpr, ke.keyExpr, other.jniKeyExpr, other.keyExpr))` |
| `JNIKeyExpr.joinViaJNI(ke, other): Result<KeyExpr>` | `runCatching { KeyExpr(JNIKeyExpr.join(ke.jniKeyExpr, ke.keyExpr, other)) }` |
| `JNIKeyExpr.concatViaJNI(ke, other): Result<KeyExpr>` | `runCatching { KeyExpr(JNIKeyExpr.concat(ke.jniKeyExpr, ke.keyExpr, other)) }` |

---

#### `ZenohId.kt` — Method renamed

Old: `JNIZenohId.toStringViaJNI(bytes)` → New: `JNIZenohId.toString(bytes)`

---

#### `Publisher.kt` — Extract bytes from domain objects

Old:
```kotlin
jniPublisher?.put(payload, encoding ?: this.encoding, attachment)
jniPublisher?.delete(attachment)
```
New (follow zenoh-java's `Publisher.kt`):
```kotlin
val enc = encoding ?: this.encoding
return runCatching { jniPublisher?.put(payload.into().bytes, enc.id, enc.schema, attachment?.into()?.bytes) }
return runCatching { jniPublisher?.delete(attachment?.into()?.bytes) }
```

---

#### `AdvancedPublisher.kt` — Extract bytes + matching listener callback setup

Old: `jniPublisher?.put(payload, encoding, attachment)` — domain types
New: Extract bytes, call `jniPublisher.put(payload.into().bytes, enc.id, enc.schema, attachment?.into()?.bytes)`

Old: `jniPublisher?.declareMatchingListener(callback, resolvedOnClose)` where callback is a Kotlin `Callback<MatchingStatus>`
New: Create a `JNIMatchingListenerCallback` lambda wrapping the Kotlin callback, then call `jniPublisher.declareMatchingListener(jniCallback, onClose)`

Old: `jniPublisher?.getMatchingStatus(): Result<Boolean>`
New: `runCatching { jniPublisher.getMatchingStatus() }` (runtime returns `Boolean`, not `Result<Boolean>`)

---

#### `Query.kt` — Extract primitives from Sample/IntoZBytes

The runtime `JNIQuery.replySuccess` / `replyDelete` / `replyError` take primitives.

Old: `jniQuery?.replySuccess(sample: Sample)` where zenoh-kotlin's `JNIQuery.replySuccess` extracted primitives internally.
New: Extract primitives from `sample` and call runtime's `jniQuery.replySuccess(sample.keyExpr.jniKeyExpr, sample.keyExpr.keyExpr, sample.payload.bytes, sample.encoding.id, sample.encoding.schema, timestampEnabled, timestampNtp64, attachment, qosExpress)` directly.

Similarly for `replyDelete` and `replyError`.

---

#### `Querier.kt` — Set up JNI callbacks

Old: `jniQuerier?.performGet(selector, callback, ...)` where zenoh-kotlin's `JNIQuerier.performGet` set up a `JNIGetCallback` lambda.
New: Set up `JNIGetCallback` and `JNIOnCloseCallback` lambdas inline in `Querier.kt`, then call `jniQuerier.get(keyExpr.jniKeyExpr, keyExpr.keyExpr, params, callback, onClose, attachmentBytes, payload, encodingId, encodingSchema)`. The callback lambda constructs `Reply` domain objects from raw JNI parameters.

---

#### `Zenoh.kt` (Scout) — Set up JNI callbacks + primitive conversion

Old: `JNIScout.scout(whatAmI: Set<WhatAmI>, callback: Callback<Hello>, receiver, onClose, config: Config?)` — domain types
New: Create `JNIScoutCallback` lambda that constructs `Hello` domain objects from raw parameters, compute `whatAmI` as Int (OR of `WhatAmI.value`), pass `config?.jniConfig`, then call `JNIScout.scout(whatAmI, jniCallback, onClose, config?.jniConfig)`.

---

#### `Logger.kt` — Remove private external fun, call runtime

- Remove `@Throws(ZError::class) private external fun startLogsViaJNI(filter: String)`.
- Replace `startLogsViaJNI(filter)` with `io.zenoh.jni.JNILogger.startLogs(filter)`.

---

### 3d. `JNILiveliness.kt` — Keep, refactor to call runtime's public JNISession methods

This file contains callback-setup adapter logic (constructing `Sample` and `Reply` domain objects from raw JNI parameters) that is not in the runtime. **Keep this file.**

- Remove the three `private external fun` declarations: `getViaJNI`, `declareTokenViaJNI`, `declareSubscriberViaJNI`.
- Remove direct access to `jniSession.sessionPtr.get()` — that field is `internal` in the runtime module and inaccessible externally.
- Replace with calls to the runtime's **public** `JNISession` methods:
  - `declareTokenViaJNI(jniSession.sessionPtr.get(), ...)` → `jniSession.declareLivelinessToken(keyExpr.jniKeyExpr, keyExpr.keyExpr)` (returns runtime `JNILivelinessToken`)
  - `declareSubscriberViaJNI(...)` → `jniSession.declareLivelinessSubscriber(keyExpr.jniKeyExpr, keyExpr.keyExpr, subCallback, history, onClose)` (returns runtime `JNISubscriber`)
  - `getViaJNI(...)` → `jniSession.livelinessGet(keyExpr.jniKeyExpr, keyExpr.keyExpr, getCallback, timeout.toMillis(), onClose)`
- After zenoh-kotlin's `JNISession.kt` is deleted, the parameter `jniSession: JNISession` resolves to the runtime's class.
- Callback interfaces (`JNISubscriberCallback`, `JNIGetCallback`, `JNIOnCloseCallback`) now come from runtime's `io.zenoh.jni.callbacks.*` — update imports.

---

### 3e. Drop-in compatible classes (close() only — no call-site adaptation)

These zenoh-kotlin domain classes only call `.close()` on their JNI objects. The runtime's versions are drop-in: update imports only.

- `Subscriber.kt` → `JNISubscriber.close()` ✅
- `Queryable.kt` → `JNIQueryable.close()` ✅
- `LivelinessToken.kt` → `JNILivelinessToken.close()` ✅  
- `MatchingListener.kt` → `JNIMatchingListener.close()` ✅
- `SampleMissListener.kt` → `JNISampleMissListener.close()` ✅
- `AdvancedSubscriber.kt` → `JNIAdvancedSubscriber.close()` ✅

---

## Phase 4: Remove All Rust Code

- Delete the entire `zenoh-jni/` directory.
- Delete `rust-toolchain.toml` at repo root.
- Verify: no `*.rs` or `Cargo.toml` files remain outside the `zenoh-java/` submodule.

---

## Phase 5: Update `examples/build.gradle.kts`

- Remove the `CompileZenohJNI` task that runs `cargo build --manifest-path ../zenoh-jni/Cargo.toml`.
- Remove `-Djava.library.path=../zenoh-jni/target/release` system property from example execution tasks.

---

## Phase 6: Update CI Workflows

### `.github/workflows/ci.yml`
- Add `submodules: recursive` to the `actions/checkout@v4` step.
- Remove zenoh-kotlin's own Rust toolchain setup steps, `cargo fmt`, `cargo clippy`, `cargo test`, `cargo build` steps.
- Keep or add Rust toolchain for compiling `zenoh-java/zenoh-jni` (the submodule's Rust crate) during CI builds with the submodule initialized.

### `.github/workflows/publish-jvm.yml`
- Remove the 6-platform cross-compilation matrix (Linux/macOS/Windows × x86_64/ARM64), all `cargo build` steps, `jni-libs` artifact download/aggregation job.
- Simplify: single `./gradlew publish -PremotePublication=true` step.

### `.github/workflows/publish-android.yml`
- Remove NDK setup (`nttld/setup-ndk`), `rustup target add` steps for Android ABIs, Cargo cross-compilation steps.

---

## Verification Checklist

1. `find . -name "*.rs" -o -name "Cargo.toml"` returns nothing outside `zenoh-java/` submodule.
2. `./gradlew :zenoh-kotlin:compileKotlinJvm` succeeds with submodule initialized.
3. `./gradlew :zenoh-kotlin:jvmTest` passes.
4. `./gradlew generatePomFileForMavenJvmPublication` — POM contains `org.eclipse.zenoh:zenoh-jni-runtime` as a dependency.
5. `./gradlew :zenoh-kotlin:dependencies --configuration jvmRuntimeClasspath` — no duplicate `io.zenoh.jni.*` class entries.
6. `./gradlew :examples:shadowJar` builds without any Cargo tasks.
7. All public types in `io.zenoh.*` retain existing signatures: `Session`, `Config`, `Publisher`, `Subscriber`, `Querier`, `Queryable`, `Query`, `KeyExpr`, `ZBytes`, `zSerialize`/`zDeserialize`, liveliness API.
8. `zSerialize`/`zDeserialize` remain declared in `commonMain` source set.

---

## Critical Files Summary

| File/Path | Change Type |
|-----------|-------------|
| `.gitmodules` | New — zenoh-java submodule at `zenoh-java`, branch `common-jni` |
| `settings.gradle.kts` | Remove `:zenoh-jni`; add gated `includeBuild("zenoh-java")` |
| `build.gradle.kts` (root) | Remove `rust-android-gradle` plugin |
| `zenoh-kotlin/build.gradle.kts` | Add zenoh-jni-runtime dep; remove Cargo/Rust tasks; remove native-bundling `isRemotePublication` logic |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/ZBytesJNIBridge.kt` | New — `expect fun serializeViaJNI` / `deserializeViaJNI` |
| `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/jni/ZBytesJNIBridge.kt` | New — `actual` calling `JNIZBytesKotlin` |
| `zenoh-kotlin/src/androidMain/kotlin/io/zenoh/jni/ZBytesJNIBridge.kt` | New — identical actual to jvmMain |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/ext/ZSerialize.kt` | Update import to bridge function |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/ext/ZDeserialize.kt` | Update import to bridge function |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/` (16 classes + JNIZBytes) | Delete all |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/` (7 interfaces) | Delete all |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNILiveliness.kt` | Keep — remove `private external fun` declarations; call runtime `JNISession` public methods |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Logger.kt` | Remove `private external fun startLogsViaJNI`; call `JNILogger.startLogs(filter)` |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt` | Remove `internal expect object ZenohLoad`; adapt JNIScout call sites |
| `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` | Delete (only contained `internal actual object ZenohLoad`) |
| `zenoh-kotlin/src/androidMain/kotlin/io/zenoh/Zenoh.kt` | Delete (only contained `internal actual object ZenohLoad`) |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt` | Major adaptation — inline adapter logic from deleted JNISession.kt; use runtime JNISession |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Config.kt` | Adapt factory methods to runtime API |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/keyexpr/KeyExpr.kt` | Adapt return-type wrapping and parameter extraction |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/config/ZenohId.kt` | Method rename: `toStringViaJNI` → `toString` |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/Publisher.kt` | Extract bytes from IntoZBytes before calling runtime |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/AdvancedPublisher.kt` | Same + matching listener JNI callback setup |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/query/Query.kt` | Extract primitives from Sample/IntoZBytes |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/query/Querier.kt` | Set up JNI callbacks inline; call runtime JNIQuerier.get |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/Subscriber.kt` | Import update only |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/query/Queryable.kt` | Import update only |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/AdvancedSubscriber.kt` | Import update only |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/liveliness/LivelinessToken.kt` | Import update only |
| `zenoh-jni/` | Delete entire directory |
| `rust-toolchain.toml` | Delete |
| `examples/build.gradle.kts` | Remove `CompileZenohJNI` task and `java.library.path` references |
| `.github/workflows/ci.yml` | Remove Rust steps; add submodule checkout |
| `.github/workflows/publish-jvm.yml` | Remove cross-compilation matrix |
| `.github/workflows/publish-android.yml` | Remove NDK/Cargo steps |

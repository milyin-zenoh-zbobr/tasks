# Implementation Plan v8: Make zenoh-kotlin Depend on zenoh-jni-runtime

## Compatibility Assessment (Planner-Verified)

**zenoh-jni-runtime IS sufficient as a replacement for zenoh-kotlin's JNI layer.** It covers all operations: session, publisher, subscriber, querier, queryable, key expressions, scouting, liveliness, serialization, and logging.

**HOWEVER, zenoh-jni-runtime is NOT a drop-in API replacement.** The runtime's JNI classes share package/class names (`io.zenoh.jni.*`) with zenoh-kotlin's own JNI adapters, but their Kotlin-facing method signatures are different: the runtime uses primitive types (`ByteArray`, `Int`, `String?`) everywhere, while zenoh-kotlin's own JNI adapters accepted domain objects (`IntoZBytes`, `Encoding`, `KeyExpr`, `Sample`, etc.) and wrapped results in `Result<T>`. The migration must adapt call sites, not just swap imports.

---

## Key Design Decisions

1. **Class name conflict**: Both codebases define `io.zenoh.jni.JNISession`, `JNIPublisher`, etc. They cannot coexist. Strategy: delete ALL zenoh-kotlin's JNI classes; domain classes hold the runtime's versions directly.

2. **Duplicate shared classes**: Both codebases define `io.zenoh.exceptions.ZError`, `io.zenoh.Target`, and `io.zenoh.ZenohLoad` with identical shapes. Strategy: delete zenoh-kotlin's local copies and rely on the runtime's versions. Public FQCNs are preserved.

3. **Adaptation strategy**: Follow zenoh-java's approach exactly — the domain classes (`Session.kt`, `Publisher.kt`, `Config.kt`, etc.) perform the domain-object → primitive conversion inline before calling runtime JNI methods. The primary reference is `zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt` and its sibling files on the `common-jni` branch.

4. **Serialization source-set migration**: `ZSerialize.kt`/`ZDeserialize.kt` are moved from `commonMain` to a new `jvmAndAndroidMain` intermediate source set (mirrors the intentional design in zenoh-jni-runtime where `JNIZBytesKotlin` is `jvmAndAndroidMain`-only, because Kotlin reflection used by type-aware serialization is not available in Kotlin/Native or Kotlin/JS). No `expect/actual` bridge is needed. Since zenoh-kotlin only targets JVM and Android, all current users of these functions are unaffected.

5. **ZenohLoad/Target**: Delete zenoh-kotlin's own `expect object ZenohLoad` and its `actual` implementations plus `Target.kt`; use the runtime's `io.zenoh.ZenohLoad` and `io.zenoh.Target` directly.

6. **Composite build gating**: Gate `includeBuild("zenoh-java")` behind `file("zenoh-java/settings.gradle.kts").exists()` so clones without submodule init resolve from Maven Central.

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

- **Add `jvmAndAndroidMain` intermediate source set** (see Phase 2).

- **Remove**:
  - `buildZenohJni` task, `buildZenohJNI()` function, all Cargo/NDK task wiring
  - `compileKotlinJvm.dependsOn("buildZenohJni")`
  - `tasks.whenObjectAdded { ... cargoBuild ... }` block
  - `tasks.withType<Test>` block setting `java.library.path` to Rust target dir
  - The `isRemotePublication`-gated `jvmMain` resource source dirs for `../jni-libs` and `../zenoh-jni/target` (keep the signing gate itself)

---

## Phase 2: Serialization Source-Set Migration (Move to `jvmAndAndroidMain`)

**Rationale**: The runtime's `JNIZBytesKotlin` (which powers Kotlin type-aware serialization) is in `jvmAndAndroidMain` because `kotlin-reflect` is not available on Kotlin/Native or Kotlin/JS. The same constraint applies to `ZSerialize.kt`/`ZDeserialize.kt` in zenoh-kotlin. Moving them to `jvmAndAndroidMain` is consistent with the runtime's intentional design and was explicitly approved by the repo owner.

**Steps**:

1. **In `zenoh-kotlin/build.gradle.kts`**, declare an intermediate source set:
   ```kotlin
   val jvmAndAndroidMain by creating {
       dependsOn(commonMain)
   }
   jvmMain.dependsOn(jvmAndAndroidMain)
   if (androidEnabled) {
       androidMain.dependsOn(jvmAndAndroidMain)
   }
   ```

2. **Create the directory** `zenoh-kotlin/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/`.

3. **Move** `ZSerialize.kt` and `ZDeserialize.kt` from `commonMain/kotlin/io/zenoh/ext/` to `jvmAndAndroidMain/kotlin/io/zenoh/ext/`.

4. **Update imports** in these files: replace `io.zenoh.jni.JNIZBytes.serializeViaJNI` / `deserializeViaJNI` with direct calls to `io.zenoh.jni.JNIZBytesKotlin.serialize(value, kType).into()` and `io.zenoh.jni.JNIZBytesKotlin.deserialize(zBytes.bytes, kType)`.

5. **No `expect/actual` bridge file needed** — the files directly import the runtime's class from the same source-set tier.

6. **`JNIZBytes.kt`** in `commonMain` is deleted (see Phase 3a).

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

Platform-specific ZenohLoad files (also delete the platform-local `Target`):
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (only contained `internal actual object ZenohLoad`)
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt` (internal enum `io.zenoh.Target` — **identical FQCN to runtime's copy**)
- `zenoh-kotlin/src/androidMain/kotlin/io/zenoh/Zenoh.kt` (same `actual object ZenohLoad`)

**Duplicate shared classes — also delete**:
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`

  Both zenoh-kotlin and zenoh-jni-runtime define `io.zenoh.exceptions.ZError` with the identical shape. Delete zenoh-kotlin's local copy and rely on the runtime's version. The public FQCN is preserved and all callers of `ZError` in zenoh-kotlin continue to compile without any import changes.

**Why Target.kt must be deleted**: `io.zenoh.Target` is defined in both `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt` and `zenoh-jni-runtime/src/jvmMain/kotlin/io/zenoh/Target.kt` with identical content. Both compile to the same `io/zenoh/Target.class` bytecode path. When zenoh-kotlin depends on zenoh-jni-runtime, having two artifacts each contributing `io.zenoh.Target` creates a duplicate-class conflict on the classpath. The zenoh-kotlin copy is only referenced from `jvmMain/Zenoh.kt` (the `actual object ZenohLoad` implementation) which is also being deleted — so deleting both together leaves no dangling references.

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
| `JNIConfig.loadDefaultConfig()` | `JNIConfig.loadDefault()` |
| `JNIConfig.loadConfigFile(path: Path)` | `JNIConfig.loadFromFile(path.toString())` |
| `JNIConfig.loadJsonConfig(s)` | `JNIConfig.loadFromJson(s)` |
| `JNIConfig.loadJson5Config(s)` | `JNIConfig.loadFromJson5(s)` |

All runtime methods return raw `JNIConfig` (not `Result<Config>`); wrap in `runCatching { Config(JNIConfig.loadXxx(...)) }` at the call sites.

---

#### `KeyExpr.kt` — Signature changes

| Old | New |
|-----|-----|
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

#### `AdvancedSubscriber.kt` — Real adaptation hotspot (NOT drop-in)

`AdvancedSubscriber.kt` delegates four groups of methods to zenoh-kotlin's local `JNIAdvancedSubscriber` adapter:
- `declareDetectPublishersSubscriber(keyExpr, history, callback, onClose, receiver)` → returns `Result<Subscriber<R>>`
- `declareBackgroundDetectPublishersSubscriber(keyExpr, history, callback, onClose)` → returns `Result<Unit>`
- `declareSampleMissListener(callback, onClose)` → returns `Result<SampleMissListener>`
- `declareBackgroundSampleMissListener(callback, onClose)` → returns `Result<Unit>`

After deletion of the local adapter, the runtime's `JNIAdvancedSubscriber` has different signatures — it takes raw JNI callback types (`JNISubscriberCallback`, `JNISampleMissListenerCallback`, `JNIOnCloseCallback`) and returns raw JNI objects (`JNISubscriber`, `JNISampleMissListener`) or throws. The domain-object construction that lived in the local adapter must be inlined into `AdvancedSubscriber.kt`.

**Adaptation strategy** (inline the adapter logic, following the same pattern as zenoh-kotlin's existing local `JNIAdvancedSubscriber.kt`):

For `declareDetectPublishersSubscriber` (and its background/handler/channel variants):
1. Construct a `JNISubscriberCallback` lambda that builds a `Sample` domain object from raw parameters (keyExpr string, payload bytes, encodingId, encodingSchema, kind int, timestampNTP64, timestampIsValid, attachmentBytes, express, priority, congestionControl) and calls `callback.run(sample)`.
2. Wrap `onClose` in a `JNIOnCloseCallback` lambda.
3. Call `jniSubscriber.declareDetectPublishersSubscriber(history, jniCallback, jniOnClose)` → returns `JNISubscriber`.
4. Wrap result in `Subscriber(keyExpr, receiver, JNISubscriber(rawPtr))`.
5. Use `runCatching { }` around the above.

For `declareSampleMissListener` (and its background/handler/channel variants):
1. Construct a `JNISampleMissListenerCallback` lambda that builds a `SampleMiss` domain object from raw parameters (zidLower, zidUpper, eid, missedCount) and calls `callback.run(miss)`.
2. Wrap `onClose` in a `JNIOnCloseCallback` lambda.
3. Call `jniSubscriber.declareSampleMissListener(jniCallback, jniOnClose)` → returns `JNISampleMissListener`.
4. Wrap result in `SampleMissListener(JNISampleMissListener(rawPtr))`.
5. Use `runCatching { }` around the above.

The field `private var jniSubscriber: JNIAdvancedSubscriber?` in `AdvancedSubscriber.kt` now resolves to the runtime's public `JNIAdvancedSubscriber` class. The `close()` / `undeclare()` method is unchanged (still calls `jniSubscriber?.close()`).

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

Note: `AdvancedSubscriber.kt` is **NOT** in this list — it requires real adaptation (see 3c above).

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
5. `./gradlew :zenoh-kotlin:dependencies --configuration jvmRuntimeClasspath` — no duplicate `io.zenoh.jni.*`, `io.zenoh.exceptions.*`, or `io.zenoh.Target` class entries.
6. `./gradlew :examples:shadowJar` builds without any Cargo tasks.
7. All public types in `io.zenoh.*` retain existing signatures: `Session`, `Config`, `Publisher`, `Subscriber`, `Querier`, `Queryable`, `Query`, `KeyExpr`, `ZBytes`, `zSerialize`/`zDeserialize`, liveliness API, `ZError`.
8. `zSerialize`/`zDeserialize` are present in the `jvmAndAndroidMain` source set (moved from `commonMain`); they remain in the published API for all supported targets (JVM, Android).
9. `io.zenoh.exceptions.ZError` resolves to runtime's single definition — no duplicate class warnings.
10. `io.zenoh.Target` resolves to runtime's single definition — no duplicate class warnings.

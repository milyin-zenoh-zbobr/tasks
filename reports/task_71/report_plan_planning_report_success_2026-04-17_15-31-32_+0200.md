# Implementation Plan v5: Make zenoh-kotlin Use zenoh-jni-runtime from zenoh-java

## Context and Rationale

PR https://github.com/eclipse-zenoh/zenoh-java/pull/465 (branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`, HEAD `c4ec1d89c246a76edd03128593fd34f6641c405d`) introduces `zenoh-jni-runtime`, a reusable Kotlin multiplatform module wrapping the Rust zenoh-jni crate. zenoh-kotlin currently duplicates all JNI wrappers internally and maintains its own Rust crate. The goal is to consume `zenoh-jni-runtime` via Gradle composite build and delete all of zenoh-kotlin's local JNI wrappers and its Rust crate.

**Closest analog**: zenoh-java's facade classes (post-PR 465) show the exact pattern for calling the runtime's JNI API.

**Note on prerequisites**: This task requires one preparatory change to the zenoh-java companion repository (described in Phase 0) before the zenoh-kotlin changes can be completed.

---

## Phase 0: Companion Commit to zenoh-java (Prerequisite)

**This phase modifies `milyin-zenoh-zbobr/zenoh-java`, branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`, before the zenoh-kotlin submodule is pinned.**

The zenoh-java runtime's `JNIZBytes` object uses `java.lang.reflect.Type` and `ByteArray` — incompatible with zenoh-kotlin's `kotlin.reflect.KType` and `ZBytes`. These cannot be bridged without new native code. The solution is to add a Kotlin-specific serializer class `KJNIZBytes` to the runtime.

### 0a. Add `KJNIZBytes.kt` to zenoh-jni-runtime

In `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/KJNIZBytes.kt`:

```kotlin
package io.zenoh.jni

import io.zenoh.ZenohLoad
import io.zenoh.bytes.ZBytes
import kotlin.reflect.KType

@PublishedApi
internal object KJNIZBytes {
    init { ZenohLoad }
    external fun serializeViaJNI(any: Any, kType: KType): ZBytes
    external fun deserializeViaJNI(zBytes: ZBytes, kType: KType): Any
}
```

This is structurally identical to zenoh-kotlin's current `JNIZBytes.kt`, only the class name changes.

### 0b. Add `KJNIZBytes` Rust functions to zenoh-jni

In `zenoh-jni/src/zbytes.rs`, add two new exported functions:
- `Java_io_zenoh_jni_KJNIZBytes_serializeViaJNI`
- `Java_io_zenoh_jni_KJNIZBytes_deserializeViaJNI`

These are exact copies of zenoh-kotlin's current KType-based implementation in `zenoh-kotlin/zenoh-jni/src/zbytes.rs` — the `KotlinType` enum, `decode_ktype()`, and the serialize/deserialize logic — retranslated to the new class name in the JNI symbol. The Java-style `JNIZBytes` functions already in the runtime remain unchanged; the new Kotlin-style functions are additive.

### 0c. Expose `KJNIZBytes` from zenoh-jni-runtime module public API surface

In `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/` ensure `KJNIZBytes.kt` is included in compilation. No additional export annotation beyond `@PublishedApi internal` is needed — this makes it accessible from inline functions in consumer modules.

### 0d. Commit and push

Commit the Phase 0 changes to `milyin-zenoh-zbobr/zenoh-java`'s `zbobr_fix-68` branch. **Record the resulting commit SHA** — it will be used as the submodule pin in Phase 1.

---

## Phase 1: Add zenoh-java as Git Submodule

In the zenoh-kotlin repository:

```bash
git submodule add https://github.com/milyin-zenoh-zbobr/zenoh-java.git zenoh-java
git -C zenoh-java checkout <SHA-from-Phase-0>
```

Commit `.gitmodules` and the submodule entry. The native Rust crate and `zenoh-jni-runtime` module are now available at `zenoh-java/zenoh-jni/` and `zenoh-java/zenoh-jni-runtime/` respectively.

---

## Phase 2: Gradle Build Configuration

### 2a. `settings.gradle.kts` (root)

- Remove `include(":zenoh-jni")`
- Add `includeBuild("zenoh-java")` with dependency substitution, conditioned on non-remote publication:

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
- The `buildZenohJni` task, `BuildMode` enum, and `buildZenohJNI` helper function
- The `configureCargo()` function and Cargo plugin portion of `configureAndroid()`
- `org.mozilla.rust-android-gradle.rust-android` plugin application
- `tasks.whenObjectAdded { ... cargoBuild ... }` block
- `jvmMain` resource `srcDir` pointing to `../zenoh-jni/target/...`

**Add:**
- `zenoh-jni-runtime` as `api` dependency in `commonMain`:
  ```kotlin
  api("org.eclipse.zenoh:zenoh-jni-runtime:${rootProject.version}")
  ```
  **Version contract**: `rootProject.version` is read from zenoh-kotlin's `version.txt` (`1.9.0`). zenoh-java uses the same version, so this coordinate resolves correctly whether using the local composite build or Maven Central. See the Publication Strategy section for the required ordering constraint.

- For `jvmMain`, preserve native library resources from the submodule (same pattern as the runtime's own `build.gradle.kts`, adjusted for the submodule path):
  ```kotlin
  val jvmMain by getting {
      if (isRemotePublication) {
          resources.srcDir("../jni-libs").include("*/**")
      } else {
          resources.srcDir("../zenoh-java/zenoh-jni/target/$buildMode")
              .include(arrayListOf("*.dylib", "*.so", "*.dll"))
      }
  }
  ```

- For `jvmTest`, **preserve** the native library resources (needed for test execution — the runtime's own build keeps this too):
  ```kotlin
  val jvmTest by getting {
      resources.srcDir("../zenoh-java/zenoh-jni/target/$buildMode")
          .include(arrayListOf("*.dylib", "*.so", "*.dll"))
  }
  ```

- **Preserve** `tasks.withType<Test>` native library path (same reason — keep it pointing to the submodule):
  ```kotlin
  tasks.withType<Test> {
      doFirst {
          systemProperty("java.library.path", "../zenoh-java/zenoh-jni/target/$buildMode")
      }
  }
  ```

- Task wiring to trigger the native build from the included build before JVM compilation (guard with `!isRemotePublication`):
  ```kotlin
  if (!isRemotePublication) {
      tasks.named("compileKotlinJvm") {
          dependsOn(gradle.includedBuild("zenoh-java").task(":zenoh-jni-runtime:buildZenohJni"))
      }
  }
  ```

### 2d. `examples/build.gradle.kts`

- Replace the `CompileZenohJNI` task (which ran `cargo build --release --manifest-path ../zenoh-jni/Cargo.toml`) with:
  ```kotlin
  tasks.register("CompileZenohJNI") {
      dependsOn(gradle.includedBuild("zenoh-java").task(":zenoh-jni-runtime:buildZenohJni"))
  }
  ```
- Update `java.library.path` in each `JavaExec` task from `../zenoh-jni/target/release` to `../zenoh-java/zenoh-jni/target/release`

---

## Phase 3: Delete Local JNI Wrapper Files

### 3a. Files to DELETE entirely (now provided by zenoh-jni-runtime)

All files under `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/`:
- `JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt`, `JNIConfig.kt`, `JNIKeyExpr.kt`
- `JNILiveliness.kt`, `JNILivelinessToken.kt`, `JNIMatchingListener.kt`, `JNIPublisher.kt`
- `JNIQuerier.kt`, `JNIQueryable.kt`, `JNIQuery.kt`, `JNISampleMissListener.kt`
- `JNIScout.kt`, `JNISession.kt`, `JNISubscriber.kt`, `JNIZenohId.kt`
- **`JNIZBytes.kt`** — deleted because the runtime also exports `io.zenoh.jni.JNIZBytes`; keeping both causes a duplicate FQCN
- Entire `callbacks/` subdirectory

Also delete:
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt` (provided by runtime)
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (ZenohLoad JVM actual — provided by runtime)
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt` (provided by runtime)
- `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` (ZenohLoad Android actual — provided by runtime)

### 3b. Update `ZSerialize.kt` and `ZDeserialize.kt`

Change the import from `io.zenoh.jni.JNIZBytes.serializeViaJNI` to `io.zenoh.jni.KJNIZBytes.serializeViaJNI` (and equivalently for `deserializeViaJNI`). No other changes to these files.

Both `zSerialize` and `zDeserialize` are `inline reified` functions. `@PublishedApi internal` on `KJNIZBytes` (in the runtime) makes it accessible from these inline functions in zenoh-kotlin — this is exactly the same pattern as `JNIZBytes` today.

### 3c. Update `Zenoh.kt` (commonMain)

Remove the `internal expect object ZenohLoad` declaration at the bottom. The public `ZenohLoad` from zenoh-jni-runtime replaces it. All other usages of `ZenohLoad` in the file remain (they now resolve to the runtime's exported `ZenohLoad`).

---

## Phase 4: Scout Migration in `Zenoh.kt`

The local `JNIScout.kt` is deleted (Phase 3a). `Zenoh.kt` must call the runtime's lower-level `JNIScout` API.

Runtime signature:
```kotlin
fun scout(whatAmI: Int, callback: JNIScoutCallback, onClose: JNIOnCloseCallback, config: JNIConfig?): JNIScout
```

For each of the `scout()` overloads in `Zenoh.kt`, replace the deleted local `JNIScout.scout(whatAmI = Set<WhatAmI>, ...)` call with:

1. Convert `Set<WhatAmI>` to a bitmask Int:
   ```kotlin
   val bitmask = whatAmI.map { it.value }.reduce { acc, v -> acc or v }
   ```
2. Assemble `JNIScoutCallback` (imported from runtime at `io.zenoh.jni.callbacks.JNIScoutCallback`):
   ```kotlin
   val scoutCallback = JNIScoutCallback { whatAmI2, id, locators ->
       callback.run(Hello(WhatAmI.fromInt(whatAmI2), ZenohId(id), locators))
   }
   ```
3. Call the runtime's `JNIScout.scout()` and wrap the result:
   ```kotlin
   runCatching {
       val jniScout = JNIScout.scout(bitmask, scoutCallback, onClose, config?.jniConfig)
       Scout(receiver, jniScout)
   }
   ```

The `Scout<R>` class holds `private var jniScout: JNIScout?`. After deleting the local `JNIScout.kt`, the import `io.zenoh.jni.JNIScout` resolves to the runtime's public class — no change needed to `Scout.kt` itself.

---

## Phase 5: Migrate `Config.kt`

The `Config` class stores `internal val jniConfig: JNIConfig` — the field type is unchanged but now resolves to the runtime's public class. Map all static factory calls:

| Old call | New call |
|----------|----------|
| `JNIConfig.loadDefaultConfig()` | `Config(JNIConfig.loadDefault())` |
| `JNIConfig.loadConfigFile(path)` | `runCatching { Config(JNIConfig.loadFromFile(path.toString())) }` |
| `JNIConfig.loadJsonConfig(raw)` | `runCatching { Config(JNIConfig.loadFromJson(raw)) }` |
| `JNIConfig.loadJson5Config(raw)` | `runCatching { Config(JNIConfig.loadFromJson(raw)) }` — the runtime's Rust `loadJsonConfigViaJNI` uses `json5::Deserializer` which parses both JSON and JSON5, so behavior is preserved |
| `JNIConfig.loadYamlConfig(raw)` | `runCatching { Config(JNIConfig.loadFromYaml(raw)) }` |
| `jniConfig.getJson(key)` (returned Result) | `runCatching { jniConfig.getJson(key) }` (runtime throws ZError) |
| `jniConfig.insertJson5(key, value)` (returned Result) | `runCatching { jniConfig.insertJson5(key, value) }` (runtime throws ZError) |

---

## Phase 6: Migrate `Session.kt`

### Session open

Old: `jniSession = JNISession(); jniSession?.open(config)?.getOrThrow()`  
New: `jniSession = JNISession.open(config.jniConfig)`

The runtime's `JNISession` holds a plain `Long sessionPtr` (not `AtomicLong`). Replace all `jniSession.sessionPtr.get()` with `jniSession.sessionPtr`.

For every session method (declarePublisher, declareSubscriber, declareQueryable, etc.) that previously called a domain-level adapter in the deleted JNI wrappers, inline the primitive extraction and delegate directly to `jniSession.*` runtime methods. Reference the zenoh-java PR's `Session.kt` for the exact primitive extraction patterns.

### Liveliness (methods now on JNISession directly)

- `JNILiveliness.declareToken(jniSession, keyExpr)` → `LivelinessToken(jniSession.declareLivelinessToken(keyExpr.jniKeyExpr, keyExpr.keyExpr))`
- `JNILiveliness.get(...)` → inline `JNIGetCallback` assembly, then `jniSession.livelinessGet(keyExpr.jniKeyExpr, keyExpr.keyExpr, getCallback, timeout.toMillis(), onClose)`
- `JNILiveliness.declareSubscriber(...)` → inline `JNISubscriberCallback` assembly, then `jniSession.declareLivelinessSubscriber(keyExpr.jniKeyExpr, keyExpr.keyExpr, subCallback, history, onClose)`

---

## Phase 7: Migrate `KeyExpr.kt`

| Old | New |
|-----|-----|
| `JNIKeyExpr.intersects(this, other)` | `JNIKeyExpr.intersects(jniKeyExpr, keyExpr, other.jniKeyExpr, other.keyExpr)` |
| `JNIKeyExpr.includes(this, other)` | `JNIKeyExpr.includes(jniKeyExpr, keyExpr, other.jniKeyExpr, other.keyExpr)` |
| `JNIKeyExpr.relationTo(this, other)` | `JNIKeyExpr.relationTo(jniKeyExpr, keyExpr, other.jniKeyExpr, other.keyExpr)` |
| `JNIKeyExpr.joinViaJNI(this, other)` | `JNIKeyExpr.join(jniKeyExpr, keyExpr, other)` |
| `JNIKeyExpr.concatViaJNI(this, other)` | `JNIKeyExpr.concat(jniKeyExpr, keyExpr, other)` |

The field `internal var jniKeyExpr: JNIKeyExpr?` now resolves to the runtime's public class.

---

## Phase 8: Migrate Domain Classes — Publisher, AdvancedPublisher, AdvancedSubscriber, Query, Querier, Logger

### `Logger.kt`
Replace `external fun startLogsViaJNI(filter: String)` call with `JNILogger.startLogs(filter)` (from runtime). Remove the local `external` declaration.

### `Publisher.kt`
Inline primitive extraction before calling runtime's `JNIPublisher`:
- `put(payload, encoding, attachment)` → extract `resolvedPayload.bytes, resolvedEncoding.id, resolvedEncoding.schema, attachment?.into()?.bytes`
- `delete(attachment)` → `jniPublisher.delete(attachment?.into()?.bytes)`

### `AdvancedPublisher.kt`
Same pattern as Publisher for `put`/`delete`. For matching listener methods, inline `JNIMatchingListenerCallback { matching -> callback.run(matching) }` assembly then call `jniPublisher.declareMatchingListener(matchingListenerCallback, resolvedOnClose)`.

### `AdvancedSubscriber.kt`
Inline `JNISubscriberCallback` and `JNISampleMissListenerCallback` assembly, then call `jniSubscriber.declareDetectPublishersSubscriber(...)` and `jniSubscriber.declareSampleMissListener(...)` directly.

### `Query.kt`
- `replySuccess(sample)` → extract `sample.keyExpr.jniKeyExpr`, `sample.keyExpr.keyExpr`, `sample.payload.bytes`, `sample.encoding.id`, `sample.encoding.schema`, timestamp fields, `attachment?.bytes`, `qos.express`; call `jniQuery.replySuccess(...)`
- `replyError(error, encoding)` → `jniQuery.replyError(error.into().bytes, encoding.id, encoding.schema)`
- `replyDelete(keyExpr, timestamp, attachment, qos)` → extract primitives, call `jniQuery.replyDelete(...)`

### `Querier.kt`
Inline `JNIGetCallback` assembly (previously in old `JNIQuerier.kt`), call `jniQuerier.get(keyExpr.jniKeyExpr, keyExpr.keyExpr, parameters, callback, onClose, attachmentBytes, payload, encodingId, encodingSchema)`.

---

## Phase 9: Delete Rust Code

- Delete entire `zenoh-jni/` directory (the Rust crate local to zenoh-kotlin)
- Delete `rust-toolchain.toml` from the zenoh-kotlin root

---

## Phase 10: Update CI Workflows

### `.github/workflows/ci.yml`
- Add `submodules: recursive` to all `actions/checkout` steps
- Remove Rust-specific steps targeting the local `zenoh-jni/`: `Cargo Format`, `Clippy Check`, `Check for feature leaks`, direct `cargo build` targeting `zenoh-jni/`
- The `buildZenohJni` Gradle task in the included build invokes `cargo` internally; Rust toolchain steps can be removed or moved to depend on composite build

### `.github/workflows/publish-jvm.yml`
- Add `submodules: recursive` to checkout step
- Remove cross-compilation matrix jobs and `cargo`/`cross build` steps that built zenoh-kotlin's own `zenoh-jni/` and collected `jni-libs/`
- Keep `./gradlew publishJvmPublicationToSonatypeRepository -PremotePublication=true`; with `remotePublication=true`, the `includeBuild` substitution is skipped and `zenoh-jni-runtime` is resolved from Maven Central

### `.github/workflows/publish-android.yml`
- Add `submodules: recursive` to checkout step
- Remove `cargo build` steps targeting zenoh-kotlin's own `zenoh-jni/`

---

## Publication Strategy

**Version contract**: zenoh-kotlin declares `"org.eclipse.zenoh:zenoh-jni-runtime:${rootProject.version}"`. `rootProject.version` is read from zenoh-kotlin's `version.txt` (`1.9.0`), which matches zenoh-java's `version.txt`. This single source of truth covers both composite-build substitution (where the version is irrelevant for resolution) and remote Maven publication.

- **Local development / CI tests**: `includeBuild("zenoh-java")` is active. `compileKotlinJvm` depends on `:zenoh-jni-runtime:buildZenohJni` in the included build. zenoh-kotlin resolves `zenoh-jni-runtime` as a project dependency.

- **Maven Central publication**: The zenoh-java pipeline **must publish `org.eclipse.zenoh:zenoh-jni-runtime:1.9.0` to Maven Central first**, before zenoh-kotlin's publication run. The joint release process must order zenoh-java publication before zenoh-kotlin publication. With `remotePublication=true`, the `includeBuild` is skipped; `org.eclipse.zenoh:zenoh-jni-runtime:${rootProject.version}` is resolved from Maven Central and becomes a transitive dependency in zenoh-kotlin's published POM.

---

## File Change Summary

| Action | Files/Paths |
|--------|-------------|
| **Add (zenoh-java repo first)** | `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/KJNIZBytes.kt`, Rust `KJNIZBytes` functions in `zenoh-jni/src/zbytes.rs` |
| **Add (zenoh-kotlin)** | `.gitmodules`, `zenoh-java/` (submodule at new SHA) |
| **Delete** | `zenoh-jni/` (entire local Rust crate), `rust-toolchain.toml`, all `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/*.kt` (including `JNIZBytes.kt`), entire `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/`, `ZError.kt`, `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt`, `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt`, `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` |
| **Modify** | `settings.gradle.kts`, root `build.gradle.kts`, `zenoh-kotlin/build.gradle.kts`, `examples/build.gradle.kts`, `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt` (remove `expect ZenohLoad`, inline Scout migration), `Config.kt`, `Session.kt`, `KeyExpr.kt`, `Liveliness.kt`, `Logger.kt`, `Publisher.kt`, `AdvancedPublisher.kt`, `AdvancedSubscriber.kt`, `Query.kt`, `Querier.kt`, `ext/ZSerialize.kt` (import KJNIZBytes), `ext/ZDeserialize.kt` (import KJNIZBytes), `.github/workflows/ci.yml`, `.github/workflows/publish-jvm.yml`, `.github/workflows/publish-android.yml` |

---

## Verification Steps

1. `./gradlew :zenoh-kotlin:compileKotlinJvm` — triggers `:zenoh-jni-runtime:buildZenohJni` in the included build; compiles without missing class errors
2. `./gradlew :zenoh-kotlin:jvmTest` — all tests pass; native library loaded via test resources and `java.library.path` pointing to `../zenoh-java/zenoh-jni/target/debug`
3. `./gradlew :examples:ZPub` — runs with `java.library.path` pointing to `../zenoh-java/zenoh-jni/target/release`
4. ZBytes serialization round-trip tests pass (confirming `KJNIZBytes` native functions present and correct)
5. Scout test or manual run confirms `Zenoh.scout(...)` works with runtime's `JNIScout`
6. `grep -r "zenoh-jni" settings.gradle.kts build.gradle.kts zenoh-kotlin/build.gradle.kts` — shows only `zenoh-java/zenoh-jni` (submodule path) and `zenoh-jni-runtime`, never `include(":zenoh-jni")`
7. No `external fun` declarations remain in zenoh-kotlin's own Kotlin source (all JNI calls go through runtime classes)
8. `ls zenoh-jni/` returns "no such directory"
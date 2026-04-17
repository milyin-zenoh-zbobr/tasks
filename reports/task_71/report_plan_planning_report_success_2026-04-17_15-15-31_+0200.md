# Implementation Plan: Make zenoh-kotlin Use zenoh-jni-runtime from zenoh-java (v4 — Final)

## Context and Rationale

PR https://github.com/eclipse-zenoh/zenoh-java/pull/465 (branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`, HEAD `c4ec1d89c246a76edd03128593fd34f6641c405d`) introduces a reusable `zenoh-jni-runtime` Kotlin multiplatform module. This module exports all JNI wrapper classes as **public** and provides native library loading. zenoh-kotlin currently duplicates all of these internally. The goal is to consume `zenoh-jni-runtime` via Gradle composite build and delete zenoh-kotlin's duplicated JNI wrappers and its own Rust crate.

**Closest analog**: zenoh-java's own facade classes (post-PR 465) show the exact pattern for calling the runtime's JNI API.

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
- The `buildZenohJni` task, `BuildMode` enum, `buildZenohJNI` helper function
- The `configureCargo()` function and Cargo plugin portion of `configureAndroid()`
- `org.mozilla.rust-android-gradle.rust-android` plugin application
- `tasks.whenObjectAdded { ... cargoBuild ... }` block
- `jvmMain` resource `srcDir` pointing to `../zenoh-jni/target/...` (the non-`isRemotePublication` branch)
- `jvmTest` resource `srcDir` pointing to `../zenoh-jni/target/...`
- `tasks.withType<Test> { systemProperty("java.library.path", ...) }` — `ZenohLoad` in zenoh-jni-runtime handles native library loading from classpath resources

**Add:**
- `zenoh-jni-runtime` as `api` dependency in `commonMain`, using the project root version:
  ```kotlin
  api("org.eclipse.zenoh:zenoh-jni-runtime:${rootProject.version}")
  ```
  Both zenoh-kotlin and zenoh-java share the same `version.txt` value (`1.9.0`), so `rootProject.version` resolves to the correct artifact version for both local composite build and remote Maven publication.

- Task wiring to trigger the native build from the included build before JVM compilation. Wrap in the same `if (!isRemotePublication)` guard:
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

## Phase 3: Update zenoh-jni-runtime's Rust Crate (in zenoh-java submodule)

**This is a required change to the zenoh-java submodule's Rust code.** The reason is a class name conflict: both zenoh-kotlin and zenoh-jni-runtime have `io.zenoh.jni.JNIZBytes`, but with incompatible JNI signatures (zenoh-kotlin uses `KType`/`ZBytes`, the runtime uses `java.lang.reflect.Type`/`ByteArray`). These cannot coexist in the same JVM. The solution is to move zenoh-kotlin's Kotlin-specific serializer into the runtime under a **different class name** (`KJNIZBytes`).

### 3a. Add `KJNIZBytes` Rust functions to `zenoh-java/zenoh-jni/src/zbytes.rs`

Add two new exported Rust functions using the **KType-based** (Kotlin-specific) implementation from zenoh-kotlin's existing `zbytes.rs`. These functions must be named `Java_io_zenoh_jni_KJNIZBytes_serializeViaJNI` and `Java_io_zenoh_jni_KJNIZBytes_deserializeViaJNI` — they are identical to the KType-based functions currently in zenoh-kotlin's `zenoh-jni/src/zbytes.rs` but with the new class name in the symbol.

The key differences from the Java-style functions already in the runtime:
- Take `kotlin.reflect.KType` instead of `java.lang.reflect.Type` as the type parameter
- Support additional Kotlin types: `UByte`, `UShort`, `UInt`, `ULong`, `Pair`, `Triple`
- Return/accept the `io.zenoh.bytes.ZBytes` Java object (not raw `ByteArray`)

This is essentially copying the existing Kotlin-specific implementation from `zenoh-kotlin/zenoh-jni/src/zbytes.rs` and inserting it into the runtime's `zbytes.rs` with the renamed symbol.

Also add `mod zenoh_kotlin_zbytes` or inline the additions to the existing `zbytes.rs` — either approach works as long as the symbols are exported from the final `.so`/`.dylib`.

---

## Phase 4: Delete/Replace Local JNI Wrapper Files

### 4a. Files to DELETE entirely (now provided by zenoh-jni-runtime)

All files under `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/`:
- `JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt`, `JNIConfig.kt`, `JNIKeyExpr.kt`
- `JNILiveliness.kt`, `JNILivelinessToken.kt`, `JNIMatchingListener.kt`, `JNIPublisher.kt`
- `JNIQuerier.kt`, `JNIQueryable.kt`, `JNIQuery.kt`, `JNISampleMissListener.kt`
- `JNIScout.kt`, `JNISession.kt`, `JNISubscriber.kt`, `JNIZenohId.kt`
- Entire `callbacks/` subdirectory
- **DO NOT DELETE `JNIZBytes.kt`** — it will be replaced in Phase 5

Also delete:
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt` (provided by runtime)
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (ZenohLoad JVM actual — provided by runtime)
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt` (provided by runtime)
- `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` (ZenohLoad Android actual — provided by runtime)

### 4b. Replace `JNIZBytes.kt` (do NOT delete — rename the class)

Replace the contents of `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIZBytes.kt` with a new class named `KJNIZBytes`:

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

The file can be renamed from `JNIZBytes.kt` to `KJNIZBytes.kt` for clarity, but the package and `external` method signatures remain unchanged. The JNI symbol names will now be `Java_io_zenoh_jni_KJNIZBytes_serializeViaJNI` / `Java_io_zenoh_jni_KJNIZBytes_deserializeViaJNI` — these match the Rust functions added in Phase 3a.

### 4c. Update `ZSerialize.kt` and `ZDeserialize.kt`

Change the import from `io.zenoh.jni.JNIZBytes.serializeViaJNI` to `io.zenoh.jni.KJNIZBytes.serializeViaJNI` (and same for `deserializeViaJNI`). No other changes to these files.

### 4d. Update `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt`

Remove the `internal expect object ZenohLoad` declaration at the bottom. The public `ZenohLoad` from zenoh-jni-runtime replaces it. All usages of `ZenohLoad` in the file remain as-is (they now resolve to the runtime's `ZenohLoad`).

---

## Phase 5: Scout Migration in `Zenoh.kt`

The local `JNIScout.kt` is deleted (Phase 4a), so `Zenoh.kt` must be updated to call the runtime's lower-level `JNIScout` API directly. The runtime's `JNIScout` signature:
```kotlin
fun scout(whatAmI: Int, callback: JNIScoutCallback, onClose: JNIOnCloseCallback, config: JNIConfig?): JNIScout
```

In each of the three `scout()` overloads in `Zenoh.kt`, replace the call to the deleted local `JNIScout.scout(whatAmI = Set<WhatAmI>, callback, receiver, onClose, config)` with inline logic:

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

The `Scout<R>` class (in `Scout.kt`) holds a `private var jniScout: JNIScout?`. After deleting the local `JNIScout.kt`, the import `io.zenoh.jni.JNIScout` resolves to the runtime's public class — no change needed to `Scout.kt` itself.

---

## Phase 6: Migrate `Config.kt`

Map all calls from the old internal `JNIConfig` to the runtime's public `JNIConfig`:

| Old call | New call |
|----------|----------|
| `JNIConfig.loadDefaultConfig()` | `Config(JNIConfig.loadDefault())` |
| `JNIConfig.loadConfigFile(path)` | `runCatching { Config(JNIConfig.loadFromFile(path.toString())) }` |
| `JNIConfig.loadJsonConfig(raw)` | `runCatching { Config(JNIConfig.loadFromJson(raw)) }` |
| `JNIConfig.loadJson5Config(raw)` | `runCatching { Config(JNIConfig.loadFromJson(raw)) }` (runtime has no json5; maps to json) |
| `JNIConfig.loadYamlConfig(raw)` | `runCatching { Config(JNIConfig.loadFromYaml(raw)) }` |
| `jniConfig.getJson(key)` (returned Result) | `runCatching { jniConfig.getJson(key) }` (runtime throws ZError) |
| `jniConfig.insertJson5(key, value)` (returned Result) | `runCatching { jniConfig.insertJson5(key, value) }` (runtime throws ZError) |

The `Config` class stores `internal val jniConfig: JNIConfig` — the field type is unchanged but now resolves to the runtime's public class.

---

## Phase 7: Migrate `Session.kt`

### Session open

Old: `jniSession = JNISession(); jniSession?.open(config)?.getOrThrow()`
New: `jniSession = JNISession.open(config.jniConfig)`

The `internal var jniSession: JNISession?` field now holds the runtime's public `JNISession` (session pointer is plain `Long`, not `AtomicLong`).

Replace all `jniSession.sessionPtr.get()` with `jniSession.sessionPtr`.

For every session method (declarePublisher, declareSubscriber, declareQueryable, etc.) that previously called a domain-level adapter in the deleted JNI wrappers, inline the primitive extraction and delegate directly to `jniSession.*` methods. Reference the zenoh-java PR's `Session.kt` for the exact primitive extraction patterns.

### Liveliness (now on JNISession directly)

- `JNILiveliness.declareToken(jniSession, keyExpr)` → `LivelinessToken(jniSession.declareLivelinessToken(keyExpr.jniKeyExpr, keyExpr.keyExpr))`
- `JNILiveliness.get(...)` → inline `JNIGetCallback` assembly, then `jniSession.livelinessGet(keyExpr.jniKeyExpr, keyExpr.keyExpr, getCallback, timeout.toMillis(), onClose)`
- `JNILiveliness.declareSubscriber(...)` → inline `JNISubscriberCallback` assembly, then `jniSession.declareLivelinessSubscriber(keyExpr.jniKeyExpr, keyExpr.keyExpr, subCallback, history, onClose)`

---

## Phase 8: Migrate `KeyExpr.kt`

| Old | New |
|-----|-----|
| `JNIKeyExpr.intersects(this, other)` | `JNIKeyExpr.intersects(jniKeyExpr, keyExpr, other.jniKeyExpr, other.keyExpr)` |
| `JNIKeyExpr.includes(this, other)` | `JNIKeyExpr.includes(jniKeyExpr, keyExpr, other.jniKeyExpr, other.keyExpr)` |
| `JNIKeyExpr.relationTo(this, other)` | `JNIKeyExpr.relationTo(jniKeyExpr, keyExpr, other.jniKeyExpr, other.keyExpr)` |
| `JNIKeyExpr.joinViaJNI(this, other)` | `JNIKeyExpr.join(jniKeyExpr, keyExpr, other)` |
| `JNIKeyExpr.concatViaJNI(this, other)` | `JNIKeyExpr.concat(jniKeyExpr, keyExpr, other)` |

The field `internal var jniKeyExpr: JNIKeyExpr?` now resolves to the runtime's public class.

---

## Phase 9: Migrate Domain Classes — Publisher, AdvancedPublisher, AdvancedSubscriber, Query, Querier, Logger

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

## Phase 10: Delete Rust Code

- Delete entire `zenoh-jni/` directory (the Rust crate local to zenoh-kotlin)
- Delete `rust-toolchain.toml` from the zenoh-kotlin root

---

## Phase 11: Update CI Workflows

### `.github/workflows/ci.yml`
- Add `submodules: recursive` to all `actions/checkout` steps
- Remove Rust-specific steps targeting the local `zenoh-jni/`: `Cargo Format`, `Clippy Check`, `Check for feature leaks`, direct `cargo build` targeting `zenoh-jni/`
- The `buildZenohJni` Gradle task in the included build invokes `cargo` internally; no explicit Rust setup needed in zenoh-kotlin's own CI beyond what the composite build handles

### `.github/workflows/publish-jvm.yml`
- Add `submodules: recursive` to checkout step
- Remove cross-compilation matrix jobs and `cargo`/`cross build` steps that built zenoh-kotlin's own `zenoh-jni/` and collected `jni-libs/`
- Keep `./gradlew publishJvmPublicationToSonatypeRepository -PremotePublication=true`; with `remotePublication=true`, the `includeBuild` substitution is skipped and `zenoh-jni-runtime` is resolved from Maven Central. The published zenoh-kotlin artifact carries `org.eclipse.zenoh:zenoh-jni-runtime:${rootProject.version}` as a transitive dependency in its POM.

### `.github/workflows/publish-android.yml`
- Add `submodules: recursive` to checkout step
- Remove `cargo build` steps targeting zenoh-kotlin's own `zenoh-jni/`
- Gradle task dependency on `zenoh-jni-runtime` (via the Android cargo plugin in the included build) handles native Android build

---

## Publication Strategy (explicit)

- **Local development / CI tests**: `includeBuild("zenoh-java")` is active (submodule present, `remotePublication` not set). `compileKotlinJvm` depends on `:zenoh-jni-runtime:buildZenohJni` in the included build. Zenoh-kotlin resolves `zenoh-jni-runtime` as a project dependency from the composite build.

- **Maven Central publication**: The zenoh-java pipeline must publish `org.eclipse.zenoh:zenoh-jni-runtime:1.9.0` to Maven Central **before** zenoh-kotlin's publication run. Then zenoh-kotlin's workflow sets `remotePublication=true`: the `includeBuild` is skipped; `org.eclipse.zenoh:zenoh-jni-runtime:${rootProject.version}` is resolved from Maven Central. The joint release process must order zenoh-java publication before zenoh-kotlin publication.

---

## File Change Summary

| Action | Files/Paths |
|--------|-------------|
| **Add** | `.gitmodules`, `zenoh-java/` (submodule), `zenoh-java/zenoh-jni/src/zbytes.rs` additions (KJNIZBytes Rust functions) |
| **Delete** | `zenoh-jni/` (entire local Rust crate), `rust-toolchain.toml`, all `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/*.kt` EXCEPT `JNIZBytes.kt`, entire `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/`, `ZError.kt`, `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt`, `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt`, `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` |
| **Modify (rename class)** | `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIZBytes.kt` → class renamed to `KJNIZBytes` |
| **Modify** | `settings.gradle.kts`, root `build.gradle.kts`, `zenoh-kotlin/build.gradle.kts`, `examples/build.gradle.kts`, `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt` (remove `expect ZenohLoad`, inline Scout migration), `Config.kt`, `Session.kt`, `KeyExpr.kt`, `Liveliness.kt`, `Logger.kt`, `Publisher.kt`, `AdvancedPublisher.kt`, `AdvancedSubscriber.kt`, `Query.kt`, `Querier.kt`, `ext/ZSerialize.kt`, `ext/ZDeserialize.kt`, `.github/workflows/ci.yml`, `.github/workflows/publish-jvm.yml`, `.github/workflows/publish-android.yml` |

---

## Verification Steps

1. `./gradlew :zenoh-kotlin:compileKotlinJvm` — triggers `:zenoh-jni-runtime:buildZenohJni` in the included build; compiles without missing class errors
2. `./gradlew :zenoh-kotlin:jvmTest` — all tests pass; native library loaded by runtime's ZenohLoad
3. `./gradlew :examples:ZPub` — runs with updated `java.library.path` pointing to `../zenoh-java/zenoh-jni/target/release`
4. ZBytes serialization round-trip tests pass (confirming `KJNIZBytes` native functions present and correct)
5. Scout test or manual run confirms `Zenoh.scout(...)` works with runtime's `JNIScout`
6. `grep -r "zenoh-jni" settings.gradle.kts build.gradle.kts zenoh-kotlin/build.gradle.kts` — shows only `zenoh-java/zenoh-jni` (submodule path) and `zenoh-jni-runtime`, never `include(":zenoh-jni")`
7. No `external fun` declarations remain in zenoh-kotlin's own Kotlin source (except in `KJNIZBytes.kt`)

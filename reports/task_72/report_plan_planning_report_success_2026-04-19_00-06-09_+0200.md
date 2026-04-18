# Implementation Plan v4: Make zenoh-kotlin Depend on zenoh-jni-runtime

## Compatibility Verification (Completed by Planner)

**zenoh-jni-runtime IS fully sufficient as a replacement for zenoh-kotlin's own JNI layer.** Verified against the `common-jni` branch of zenoh-java (PR #466):

- All 16 JNI adapter class names match between zenoh-kotlin and zenoh-jni-runtime (`io.zenoh.jni.*`)
- All 7 callback interface names match (`io.zenoh.jni.callbacks.*`)
- `JNIZBytesKotlin` (runtime's `jvmAndAndroidMain`) provides `serialize(any: Any, kType: KType): ByteArray` and `deserialize(bytes: ByteArray, kType: KType): Any` — public object, directly usable
- `JNILogger` (runtime's `commonMain`) provides `public fun startLogs(filter: String)` — directly callable from zenoh-kotlin's `commonMain`
- Runtime `JNISession` exposes **public** wrapper methods: `declareLivelinessToken(...)`, `declareLivelinessSubscriber(...)`, `livelinessGet(...)` — the `...ViaJNI` variants are `private external` and NOT callable from outside the runtime
- `ZenohLoad` expect object is provided by the runtime (package `io.zenoh`, public visibility)
- `JNISession.sessionPtr` is `internal Long` — zenoh-kotlin domain code must never directly access it; use the runtime's public methods only

---

## Key Design Decisions

1. **Class name conflict**: Both zenoh-kotlin and zenoh-jni-runtime define classes with identical fully-qualified names (`io.zenoh.jni.JNISession`, etc.). They cannot coexist on the classpath. Strategy: delete ALL zenoh-kotlin's JNI classes and have the domain classes hold/use the runtime's equivalents directly.

2. **Serialization source-set mismatch**: Runtime's `JNIZBytesKotlin` lives in `jvmAndAndroidMain` and cannot be called from `commonMain`. Solution: introduce an internal `expect/actual` bridge in zenoh-kotlin so that `ZSerialize.kt`/`ZDeserialize.kt` remain in `commonMain` (no API change), with `actual` implementations in `jvmMain` and `androidMain` calling `JNIZBytesKotlin`.

3. **Publication signing**: The `remotePublication`/`isRemotePublication` property controls signing for Maven Central publishing and must be preserved. Only remove its use for native-artifact bundling (the `../jni-libs` and `../zenoh-jni/target` resource source dirs).

4. **Composite build gating**: Gate `includeBuild("zenoh-java")` behind `file("zenoh-java/settings.gradle.kts").exists()` so ordinary clones without submodule init resolve `zenoh-jni-runtime` from Maven Central.

5. **Logger**: `Logger.kt` in `commonMain` has a `private external fun startLogsViaJNI`. Remove this external declaration and delegate directly to `io.zenoh.jni.JNILogger.startLogs(filter)` from the runtime's `commonMain`.

6. **Liveliness**: Keep `JNILiveliness.kt` (it has adapter logic for constructing `Sample`/`Reply` domain objects), but remove its `private external fun` declarations and replace them with calls to the runtime `JNISession`'s public methods: `declareLivelinessToken(...)`, `declareLivelinessSubscriber(...)`, `livelinessGet(...)`.

---

## Phase 0: Add zenoh-java as Git Submodule

Add zenoh-java at path `zenoh-java`, pointing to the `common-jni` branch:
```
git submodule add -b common-jni https://github.com/eclipse-zenoh/zenoh-java.git zenoh-java
```

**Files created**: `.gitmodules`

---

## Phase 1: Update Gradle Build Configuration

### `settings.gradle.kts` (root)
- Remove `:zenoh-jni` from `include()`.
- Add conditional composite build:
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
  Without submodule: resolves from Maven Central.

### Root `build.gradle.kts`
- Remove `org.mozilla.rust-android-gradle:plugin` from buildscript dependencies.
- Keep `com.android.tools.build:gradle` (Android target remains in zenoh-kotlin).

### `zenoh-kotlin/build.gradle.kts`
**Add dependency** (version from `version.txt`):
```kotlin
commonMain.dependencies {
    implementation("org.eclipse.zenoh:zenoh-jni-runtime:<version>")
}
```

**Remove entirely:**
- `BuildMode` enum
- `buildZenohJni` task registration and `buildZenohJNI()` function
- `compileKotlinJvm.dependsOn("buildZenohJni")` task wiring
- `configureCargo()` function and its invocation
- `configureAndroid()` NDK/Cargo-specific sections (keep the Android target declaration itself)
- `tasks.whenObjectAdded { ... cargoBuild ... }` block
- `tasks.withType<Test>` block that sets `java.library.path` to the Rust target dir
- The `isRemotePublication`-gated `jvmMain` resource source dirs for `../jni-libs` and `../zenoh-jni/target` (only these lines; keep the signing gate `signing { isRequired = isRemotePublication }`)

---

## Phase 2: Fix the Serialization Source-Set Mismatch (Preserves Public API)

**Problem**: `ZSerialize.kt`/`ZDeserialize.kt` are in `commonMain` and currently import `io.zenoh.jni.JNIZBytes.serializeViaJNI` (zenoh-kotlin's own `commonMain` class). After deleting zenoh-kotlin's `JNIZBytes.kt`, `commonMain` cannot reach the runtime's `JNIZBytesKotlin` (which is in `jvmAndAndroidMain` of the runtime).

**Solution**: Add an internal `expect/actual` bridge in zenoh-kotlin.

**New file `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/ZBytesJNIBridge.kt`:**
```kotlin
package io.zenoh.jni

import io.zenoh.bytes.ZBytes
import kotlin.reflect.KType

@PublishedApi
internal expect fun serializeViaJNI(value: Any, kType: KType): ZBytes

@PublishedApi
internal expect fun deserializeViaJNI(zBytes: ZBytes, kType: KType): Any
```

**New file `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/jni/ZBytesJNIBridge.kt`:**
```kotlin
package io.zenoh.jni

import io.zenoh.bytes.ZBytes
import io.zenoh.bytes.into
import kotlin.reflect.KType

@PublishedApi
internal actual fun serializeViaJNI(value: Any, kType: KType): ZBytes =
    JNIZBytesKotlin.serialize(value, kType).into()

@PublishedApi
internal actual fun deserializeViaJNI(zBytes: ZBytes, kType: KType): Any =
    JNIZBytesKotlin.deserialize(zBytes.bytes, kType)
```

**New file `zenoh-kotlin/src/androidMain/kotlin/io/zenoh/jni/ZBytesJNIBridge.kt`:**
Identical to the jvmMain version.

**`ZSerialize.kt`** and **`ZDeserialize.kt`** in `commonMain` remain in place. Only update their imports to use the bridge functions (which now live in the same package `io.zenoh.jni`). The signatures and public behavior are identical.

---

## Phase 3: Delete zenoh-kotlin's JNI Classes and Refactor Adapters

### What gets deleted:
- All 15 JNI adapter classes in `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/`:
  `JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt`, `JNIConfig.kt`, `JNIKeyExpr.kt`, `JNILivelinessToken.kt`, `JNILogger.kt`, `JNIMatchingListener.kt`, `JNIPublisher.kt`, `JNIQuerier.kt`, `JNIQuery.kt`, `JNIQueryable.kt`, `JNISampleMissListener.kt`, `JNIScout.kt`, `JNISession.kt`, `JNISubscriber.kt`, `JNIZenohId.kt`, `JNIZBytes.kt`
- All 7 callback interfaces in `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/`
- Platform-specific ZenohLoad implementations:
  - `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (the full file — it only contains `internal actual object ZenohLoad`)
  - `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` (the full file — same)
- The `internal expect object ZenohLoad` declaration at the bottom of `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt` (keep the rest of `Zenoh.kt` including the `Zenoh` public object)

### What gets refactored:

**`Logger.kt`** (small change):
- Remove `@Throws(ZError::class) private external fun startLogsViaJNI(filter: String)`.
- In the `start(filter: String)` function, replace `startLogsViaJNI(filter)` with `io.zenoh.jni.JNILogger.startLogs(filter)`. `JNILogger` is in the runtime's `commonMain`, so it's directly accessible.

**`JNILiveliness.kt`** (keep, refactor):
- Keep the adapter logic that constructs `Sample`, `Reply`, `Hello` domain objects from raw JNI parameters (callback lambdas). This logic is not in the runtime.
- Remove the three `private external fun` declarations at the bottom: `getViaJNI`, `declareTokenViaJNI`, `declareSubscriberViaJNI`.
- After zenoh-kotlin's own `JNISession.kt` is deleted, the parameter `jniSession: JNISession` resolves to the runtime's `io.zenoh.jni.JNISession`.
- Replace the deleted external calls with the runtime's **public** methods on `JNISession` (do NOT use `...ViaJNI` suffixed methods — those are `private external` on the runtime and inaccessible):
  - `declareTokenViaJNI(jniSession.sessionPtr.get(), keyExpr.jniKeyExpr?.ptr ?: 0, keyExpr.keyExpr)` → `jniSession.declareLivelinessToken(keyExpr.jniKeyExpr, keyExpr.keyExpr)` (returns runtime's `JNILivelinessToken`)
  - `declareSubscriberViaJNI(jniSession.sessionPtr.get(), ...)` → `jniSession.declareLivelinessSubscriber(keyExpr.jniKeyExpr, keyExpr.keyExpr, subCallback, history, onClose)` (returns runtime's `JNISubscriber`)
  - `getViaJNI(jniSession.sessionPtr.get(), ...)` → `jniSession.livelinessGet(keyExpr.jniKeyExpr, keyExpr.keyExpr, getCallback, timeout.toMillis(), onClose)`
- The callback types (`JNISubscriberCallback`, `JNIGetCallback`, `JNIOnCloseCallback`) now come from runtime's `io.zenoh.jni.callbacks.*` — update imports.

**`Session.kt`** (update JNI type references):
- The `var jniSession: JNISession?` field now refers to the runtime's `io.zenoh.jni.JNISession`. No structural change needed since `Session.kt` calls methods on `jniSession` without directly accessing `sessionPtr`.
- Update the initialization: change `jniSession = JNISession()` then `.open(config)` to `jniSession = JNISession.open(jniConfig)` using the runtime's companion factory method.
- All other `jniSession` method calls (e.g., `jniSession?.declarePublisher(...)`) continue to work as-is since the runtime provides the same public method names.

**`Config.kt`**: Update to use the runtime's `JNIConfig` (same package, same class name — just an import change after deletion of zenoh-kotlin's version).

**All other domain classes** referencing deleted JNI types (`Publisher.kt`, `Subscriber.kt`, `Queryable.kt`, `Query.kt`, `Querier.kt`, `KeyExpr.kt`, etc.): Update imports to resolve to the runtime's `io.zenoh.jni.*` versions. The class names are identical, so this is primarily an import/resolution change.

**Callback interface usages**: All references to `JNISubscriberCallback`, `JNIGetCallback`, etc. are resolved from the runtime's `io.zenoh.jni.callbacks.*` after deleting zenoh-kotlin's own versions. Update imports throughout.

---

## Phase 4: Remove All Rust Code

- Delete the entire `zenoh-jni/` directory (Rust source, `Cargo.toml`, `Cargo.lock`, `build.rs`).
- Delete `rust-toolchain.toml` at repo root.
- Verify: `find . -name "*.rs" -o -name "Cargo.toml"` returns nothing outside `zenoh-java/` submodule.

---

## Phase 5: Update `examples/build.gradle.kts`

- Remove the `CompileZenohJNI` task that runs `cargo build --manifest-path ../zenoh-jni/Cargo.toml`.
- Remove `-Djava.library.path=../zenoh-jni/target/release` system property from example execution tasks.
- zenoh-jni-runtime's `ZenohLoad` handles native library loading for examples.

---

## Phase 6: Update CI Workflows

### `.github/workflows/ci.yml`
- Remove: Rust toolchain setup (`rustup show`, `rustfmt`, `clippy`), `cargo fmt`, `cargo clippy`, `cargo test`, `cargo build` steps.
- Add `submodules: recursive` to the `actions/checkout@v4` step — CI must init the zenoh-java submodule to resolve zenoh-jni-runtime from source during the build.
- Since the composite build uses the submodule source which compiles native Rust (from `zenoh-java/zenoh-jni`), Rust toolchain is still needed in CI — but it's the submodule's build that requires it, not zenoh-kotlin's own. Keep a Rust toolchain setup step for the composite build, OR configure CI to resolve from a published Maven snapshot once PR #466 is merged.

### `.github/workflows/publish-jvm.yml`
- Remove: 6-platform cross-compilation matrix (Linux x86_64/ARM64, macOS x86_64/ARM64, Windows x86_64/ARM64), all `cargo build` steps, `jni-libs` artifact download/aggregation job.
- Publish step: `./gradlew publish -PremotePublication=true` with no pre-built native artifact requirement.

### `.github/workflows/publish-android.yml`
- Remove: NDK setup (`nttld/setup-ndk`), `rustup target add` steps for Android ABIs, Cargo cross-compilation steps.

---

## Critical Files Summary

| File/Path | Change |
|-----------|--------|
| `.gitmodules` | New — zenoh-java submodule at `zenoh-java`, branch `common-jni` |
| `settings.gradle.kts` | Remove `:zenoh-jni`; add gated `includeBuild("zenoh-java")` |
| `build.gradle.kts` (root) | Remove `rust-android-gradle` plugin from buildscript |
| `zenoh-kotlin/build.gradle.kts` | Add zenoh-jni-runtime dep; remove Cargo/Rust tasks; remove native-bundling `isRemotePublication` logic; keep signing gate |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/ZBytesJNIBridge.kt` | New — `expect fun serializeViaJNI` / `deserializeViaJNI` |
| `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/jni/ZBytesJNIBridge.kt` | New — `actual` implementations calling `JNIZBytesKotlin` + wrapping in `ZBytes` |
| `zenoh-kotlin/src/androidMain/kotlin/io/zenoh/jni/ZBytesJNIBridge.kt` | New — identical actual to jvmMain |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/ext/ZSerialize.kt` | Update import: use bridge function (no structural change) |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/ext/ZDeserialize.kt` | Update import: use bridge function (no structural change) |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/` (16 classes + JNIZBytes) | Delete all |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/` (7 interfaces) | Delete all; update callers' imports |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNILiveliness.kt` | KEEP — refactor: remove `private external fun` declarations; call runtime `JNISession` public methods |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Logger.kt` | Remove `private external fun startLogsViaJNI`; call `JNILogger.startLogs(filter)` |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt` | Remove `internal expect object ZenohLoad` declaration (keep `Zenoh` object) |
| `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` | Delete (only contained `internal actual object ZenohLoad`) |
| `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` | Delete (only contained `internal actual object ZenohLoad`) |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt` | Update `JNISession` reference to runtime's; update initialization call |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Config.kt` | Update `JNIConfig` import to runtime's version |
| Other domain classes referencing deleted JNI types | Update imports to resolve to runtime's `io.zenoh.jni.*` |
| `zenoh-jni/` | Delete entire directory |
| `rust-toolchain.toml` | Delete |
| `examples/build.gradle.kts` | Remove `CompileZenohJNI` task and `java.library.path` references |
| `.github/workflows/ci.yml` | Remove Rust steps; add submodule checkout |
| `.github/workflows/publish-jvm.yml` | Remove cross-compilation matrix and artifact aggregation |
| `.github/workflows/publish-android.yml` | Remove NDK/Cargo steps |

---

## Verification

1. **No Rust in zenoh-kotlin**: `find . -name "*.rs" -o -name "Cargo.toml"` returns nothing outside `zenoh-java/` submodule.
2. **Compilation**: `./gradlew :zenoh-kotlin:compileKotlinJvm` succeeds with submodule initialized.
3. **JVM tests**: `./gradlew :zenoh-kotlin:jvmTest` passes.
4. **POM check**: `./gradlew generatePomFileForMavenJvmPublication` — confirm `org.eclipse.zenoh:zenoh-jni-runtime` appears as a dependency.
5. **No classpath duplicates**: `./gradlew :zenoh-kotlin:dependencies --configuration jvmRuntimeClasspath` — no duplicate `io.zenoh.jni.*` class entries.
6. **Examples build**: `./gradlew :examples:shadowJar` builds without any Cargo tasks.
7. **API unchanged**: All public types in `io.zenoh.*` (`Session`, `Config`, `Publisher`, `Subscriber`, `Querier`, `Queryable`, `Query`, `KeyExpr`, `ZBytes`, `zSerialize`, `zDeserialize`, liveliness API) retain existing signatures.
8. **`zSerialize`/`zDeserialize` in commonMain**: Confirm these functions remain in `commonMain` source set (not moved to a platform source set).

# Implementation Plan v7: Make zenoh-kotlin Use zenoh-jni-runtime from zenoh-java

## Context and Rationale

PR https://github.com/eclipse-zenoh/zenoh-java/pull/465 (branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`, current HEAD `b26fba7`) introduces `zenoh-jni-runtime`, a reusable Kotlin multiplatform module wrapping the Rust zenoh-jni crate. zenoh-kotlin currently duplicates all JNI wrappers internally and maintains its own Rust crate. The goal is to consume `zenoh-jni-runtime` via Gradle composite build (for local dev) / Maven Central (for publication) and delete all of zenoh-kotlin's local JNI wrapper Kotlin files and its Rust crate.

**Closest analog**: zenoh-java's own facade classes (post-PR 465) show the exact pattern for calling the runtime's JNI API, and zenoh-java's `publish-jvm.yml` / `publish-android.yml` show what simplified publication workflows look like once the runtime is in place.

**Prerequisite note**: This task requires one preparatory commit to the zenoh-java companion repository (Phase 0) to add `KJNIZBytes`. Phase 0 must be pushed before the submodule is pinned in Phase 1.

**Workspace reference**: The zenoh-java branch workspace is accessible at `~/tasks/base/workspaces/zenoh-java/task-68/zenoh-java/`. All file references below can be verified against that location.

---

## Blocking issues corrected in v7 (versus v6)

| Issue (ctx_rec_14) | Resolution in v7 |
|---|---|
| `publish-github` job (crates publication) not removed | Phase 2g explicitly removes it from `release.yml` |
| JVM publication story internally inconsistent | Phase 2e redesigns `publish-jvm.yml` to drop all Rust; zenoh-kotlin's JVM JAR has zero native libs; they live in zenoh-jni-runtime's artifact |
| Android publication story internally inconsistent | Phase 2f redesigns `publish-android.yml` to drop all Rust/NDK; same reasoning |
| `jvmMain` native resource wiring incorrect | Phase 2c: for `isRemotePublication`, no native resources in zenoh-kotlin; for local only, submodule path |
| Submodule SHA was stale | Updated to current HEAD `b26fba7` |
| `bump-and-tag.bash` still touched Cargo.toml | Phase 2h explicitly removes Cargo version bumping |

---

## Phase 0: Companion Commit to zenoh-java (Prerequisite)

This phase modifies `milyin-zenoh-zbobr/zenoh-java`, branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`. Changes must be committed and pushed before the zenoh-kotlin submodule is pinned.

### 0a. Add `KJNIZBytes.kt` to zenoh-jni-runtime

Create `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/KJNIZBytes.kt`:

```kotlin
package io.zenoh.jni

import io.zenoh.ZenohLoad
import io.zenoh.bytes.ZBytes
import kotlin.reflect.KType

public object KJNIZBytes {
    init { ZenohLoad }
    external fun serializeViaJNI(any: Any, kType: KType): ZBytes
    external fun deserializeViaJNI(zBytes: ZBytes, kType: KType): Any
}
```

**Visibility is critical**: `KJNIZBytes` MUST be `public`, not `@PublishedApi internal`. The `@PublishedApi internal` modifier is only accessible from inline functions within the *same* Kotlin module. zenoh-kotlin is a different Gradle module that consumes zenoh-jni-runtime as a dependency, so `internal` would cause a compilation error in zenoh-kotlin. Making it `public` allows zenoh-kotlin's `ZSerialize.kt` / `ZDeserialize.kt` to import it directly.

### 0b. Add Rust JNI functions to zenoh-jni

In `zenoh-jni/src/zbytes.rs`, add two exported Rust functions:
- `Java_io_zenoh_jni_KJNIZBytes_serializeViaJNI`
- `Java_io_zenoh_jni_KJNIZBytes_deserializeViaJNI`

These are additive copies of zenoh-kotlin's existing KType-based serialize/deserialize logic (the `KotlinType` enum, `decode_ktype()`, and the serialize/deserialize logic), translated to the new JNI class name `KJNIZBytes`. The existing Java-style `JNIZBytes` functions are unchanged.

### 0c. Commit and push

Commit Phase 0 changes to the zenoh-java branch. Record the resulting commit SHA — it becomes the submodule pin in Phase 1. Update the plan's submodule SHA accordingly before implementation.

---

## Phase 1: Add zenoh-java as Git Submodule

```bash
git submodule add https://github.com/milyin-zenoh-zbobr/zenoh-java.git zenoh-java
git -C zenoh-java checkout <SHA-from-Phase-0>
```

Commit `.gitmodules` and the submodule entry.

**Note on URL**: This points at the fork `milyin-zenoh-zbobr/zenoh-java.git` because the upstream PR #465 is not yet merged. Once that PR is merged into `eclipse-zenoh/zenoh-java`, the submodule URL and pin should be updated to the upstream repository.

After this phase, the composite build can reference `zenoh-java/zenoh-jni/` (Rust crate) and `zenoh-java/zenoh-jni-runtime/` (Kotlin module).

---

## Phase 2: Build Configuration and CI/CD Workflow Changes

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

When `isRemotePublication=true`, the composite build is absent and Gradle resolves `zenoh-jni-runtime` from Maven Central. This requires that zenoh-jni-runtime is already published to Maven Central before zenoh-kotlin can publish remotely — see publication sequencing note at end.

### 2b. Root `build.gradle.kts`

- Remove `classpath("org.mozilla.rust-android-gradle:plugin:0.9.6")` from `buildscript.dependencies`
- Remove `id("org.mozilla.rust-android-gradle.rust-android") version "0.9.6" apply false` from `plugins`

### 2c. `zenoh-kotlin/build.gradle.kts`

**Remove:**
- The `buildZenohJni` task, `BuildMode` enum, and `buildZenohJNI` helper function
- The `configureCargo()` function and Cargo plugin portion of `configureAndroid()`
- `org.mozilla.rust-android-gradle.rust-android` plugin application
- `tasks.whenObjectAdded { ... cargoBuild ... }` block
- `tasks.named("compileKotlinJvm") { dependsOn("buildZenohJni") }`
- All `jvmMain` and `jvmTest` resource srcDirs pointing to `../zenoh-jni/target/...`
- `tasks.withType<Test> { systemProperty("java.library.path", "../zenoh-jni/target/...") }` (will be replaced with submodule path below)

**Add:**
- `zenoh-jni-runtime` as `api` dependency in `commonMain` (using `api` so consumers get it transitively):
  ```kotlin
  api("org.eclipse.zenoh:zenoh-jni-runtime:${rootProject.version}")
  ```
  Version contract: `rootProject.version` is read from `version.txt` (`1.9.0`). zenoh-java uses the same version scheme, so this resolves correctly against both the composite build and Maven Central.

- For `jvmMain`, only include native library resources for LOCAL development. For remote publication, native libs are exclusively in zenoh-jni-runtime's published JAR — do NOT bundle them again in zenoh-kotlin's artifact:
  ```kotlin
  val jvmMain by getting {
      if (!isRemotePublication) {
          resources.srcDir("../zenoh-java/zenoh-jni/target/$buildMode")
              .include(arrayListOf("*.dylib", "*.so", "*.dll"))
      }
      // For remote publication: no native libs here.
      // They live in zenoh-jni-runtime's published JAR, which is a transitive dependency.
  }
  ```

- For `jvmTest`, always include native library resources (needed for local test execution):
  ```kotlin
  val jvmTest by getting {
      resources.srcDir("../zenoh-java/zenoh-jni/target/$buildMode")
          .include(arrayListOf("*.dylib", "*.so", "*.dll"))
  }
  ```

- Update test `java.library.path` to point to submodule:
  ```kotlin
  tasks.withType<Test> {
      doFirst {
          systemProperty("java.library.path", "../zenoh-java/zenoh-jni/target/$buildMode")
      }
  }
  ```

- Task wiring to trigger native build from included build before JVM compilation (guard with `!isRemotePublication`):
  ```kotlin
  if (!isRemotePublication) {
      tasks.named("compileKotlinJvm") {
          dependsOn(gradle.includedBuild("zenoh-java").task(":zenoh-jni-runtime:buildZenohJni"))
      }
  }
  ```

### 2d. `examples/build.gradle.kts`

Read `isRemotePublication` at top of file:
```kotlin
val isRemotePublication = project.findProperty("remotePublication")?.toString()?.toBoolean() == true
```

Replace the current `CompileZenohJNI` task (which ran `cargo build` on `../zenoh-jni/Cargo.toml`) with a guarded version:
```kotlin
tasks.register("CompileZenohJNI") {
    if (!isRemotePublication) {
        dependsOn(gradle.includedBuild("zenoh-java").task(":zenoh-jni-runtime:buildZenohJni"))
    }
}
```

**Critical**: `gradle.includedBuild("zenoh-java")` must only be called when `!isRemotePublication`. When `-PremotePublication=true`, there is no included build, so any unconditional reference would fail during Gradle configuration phase.

Update `java.library.path` in each `JavaExec` task from `../zenoh-jni/target/release` to `../zenoh-java/zenoh-jni/target/release`.

### 2e. Rewrite `publish-jvm.yml`

**Architecture after migration**: zenoh-kotlin's published JVM JAR is pure Kotlin with no native libs bundled. Native libs live exclusively in `zenoh-jni-runtime`'s JVM JAR, which is a transitive dependency. End users who depend on `zenoh-kotlin` also pull `zenoh-jni-runtime` (via `api` dep), and `ZenohLoad` (in zenoh-jni-runtime) handles loading the native lib from its JAR's resources.

**New `publish-jvm.yml` structure** (replaces the current multi-job matrix workflow):

```yaml
name: Publish (JVM)
on:
  workflow_call:
    inputs:
      snapshot:
        required: true
        type: boolean
        default: false
      branch:
        type: string
        required: false
      maven_publish:
        type: boolean
        required: false
        default: true

jobs:
  publish_jvm_package:
    name: Publish JVM package
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - name: Checkout source code
        uses: actions/checkout@v4
        with:
          ref: ${{ inputs.branch }}
          submodules: recursive

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 11

      - name: Setup Gradle
        uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: 8.12.1

      - name: Gradle Wrapper
        run: gradle wrapper

      - name: Set pub mode env var
        run: |
          if [[ "${{ inputs.snapshot }}" == "true" ]]; then
            echo "PUB_MODE=-PSNAPSHOT" >> $GITHUB_ENV
          else
            echo "RELEASE=closeAndReleaseSonatypeStagingRepository" >> $GITHUB_ENV
          fi

      - if: ${{ inputs.maven_publish == true }}
        name: Gradle Publish JVM Package to Maven Central repository
        run: |
          ./gradlew publishJvmPublicationToSonatypeRepository ${{ env.RELEASE }} --info -PremotePublication=true ${{ env.PUB_MODE }}
        env:
          CENTRAL_SONATYPE_TOKEN_USERNAME: ${{ secrets.CENTRAL_SONATYPE_TOKEN_USERNAME }}
          CENTRAL_SONATYPE_TOKEN_PASSWORD: ${{ secrets.CENTRAL_SONATYPE_TOKEN_PASSWORD }}
          ORG_GPG_KEY_ID: ${{ secrets.ORG_GPG_KEY_ID }}
          ORG_GPG_SUBKEY_ID: ${{ secrets.ORG_GPG_SUBKEY_ID }}
          ORG_GPG_PRIVATE_KEY: ${{ secrets.ORG_GPG_PRIVATE_KEY }}
          ORG_GPG_PASSPHRASE: ${{ secrets.ORG_GPG_PASSPHRASE }}
```

Key changes vs current `publish-jvm.yml`:
- **Remove** the entire `builds` matrix job (6 cross-compilation targets, Rust toolchain setup, `cargo build`, packaging `.zip` files, uploading artifacts)
- **Remove** the `Create resources destination` / `Download result of previous builds` steps
- **Remove** `CARGO_TERM_COLOR` env variable
- **Add** `submodules: recursive` to checkout (so zenoh-java submodule is available, though not built — it's the remote publication path)
- Actually for remote publication the submodule isn't even needed at all; but it doesn't hurt

### 2f. Rewrite `publish-android.yml`

Same reasoning as 2e. Android native `.so` files for all ABI targets are in `zenoh-jni-runtime`'s Android AAR. AGP merges JNI libs from transitive AAR dependencies automatically.

Remove:
- `nttld/setup-ndk@v1` step
- `Install Rust toolchain` step  
- `Setup Rust toolchains` (add armv7, i686, aarch64, x86_64 Android targets) step
- `CARGO_TERM_COLOR` env variable

Keep:
- Checkout with `submodules: recursive`
- Java/Gradle setup
- The Gradle publish command: `./gradlew publishAndroidReleasePublicationToSonatypeRepository ... -PremotePublication=true -Pandroid=true`

### 2g. Remove `publish-github` job from `release.yml`

**Remove entirely** the `publish-github` job from `.github/workflows/release.yml`:

```yaml
# DELETE THIS ENTIRE JOB:
publish-github:
  needs: [tag, publish-android, publish-jvm]
  runs-on: macos-latest
  steps:
    - uses: eclipse-zenoh/ci/publish-crates-github@main
      with:
        repo: ${{ github.repository }}
        live-run: ${{ inputs.live-run || false }}
        version: ${{ needs.tag.outputs.version }}
        branch: ${{ needs.tag.outputs.branch }}
        github-token: ${{ secrets.BOT_TOKEN_WORKFLOW }}
```

After removing `zenoh-jni/`, zenoh-kotlin owns no Rust crate. Publishing a crate from this repository has no meaning and the workflow would fail (no `Cargo.toml` to publish from). The `eclipse-zenoh/ci/publish-crates-github@main` action publishes Rust crates, which no longer exist in zenoh-kotlin.

### 2h. Update `ci/scripts/bump-and-tag.bash`

Remove all Cargo-related operations, since zenoh-kotlin no longer owns a Rust crate:

- **Remove**: `cargo +stable install toml-cli`
- **Remove**: `toml_set_in_place zenoh-jni/Cargo.toml "package.version" "$version"`
- **Remove**: `git commit version.txt zenoh-jni/Cargo.toml -m "chore: Bump version to ..."`
- **Remove**: The entire `if [[ "$bump_deps_pattern" != '' ]]; then` block (which bumps `zenoh-jni/Cargo.toml` dependency versions, runs `cargo check`, and commits `Cargo.toml` / `Cargo.lock`)
- **Remove**: Variables `bump_deps_pattern`, `bump_deps_version`, `bump_deps_branch` (no longer needed)

**Replace** the git commit with just version.txt:
```bash
git commit version.txt -m "chore: Bump version to \`$version\`"
```

Keep: `git tag`, `git push origin`, `git push --force origin "$version"`.

---

## Phase 3: Delete Local JNI Wrapper Files

### 3a. Files to DELETE entirely

All files under `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/`:
- `JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt`, `JNIConfig.kt`, `JNIKeyExpr.kt`
- `JNILiveliness.kt`, `JNILivelinessToken.kt`, `JNIMatchingListener.kt`, `JNIPublisher.kt`
- `JNIQuerier.kt`, `JNIQueryable.kt`, `JNIQuery.kt`, `JNISampleMissListener.kt`
- `JNIScout.kt`, `JNISession.kt`, `JNISubscriber.kt`, `JNIZenohId.kt`
- **`JNIZBytes.kt`** — deleted because both zenoh-kotlin and the runtime expose `io.zenoh.jni.JNIZBytes`; keeping both causes duplicate FQCN
- Entire `callbacks/` subdirectory

Also delete:
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt` (provided by runtime at same FQCN)
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (the `internal actual object ZenohLoad` implementation — replaced by runtime's `public actual object ZenohLoad`)
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt` (`internal enum class Target` — replaced by runtime's `public enum class Target`)
- `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` (the `internal actual object ZenohLoad` with `System.loadLibrary` — replaced by runtime's Android actual)

### 3b. Remove `ZenohLoad` expect declaration from `commonMain/Zenoh.kt`

Line 151 in `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt` currently reads:
```kotlin
internal expect object ZenohLoad
```

Delete this line. The usages of `ZenohLoad` at lines 56, 76, 102, 125, 141 now resolve to `io.zenoh.ZenohLoad` from the `zenoh-jni-runtime` dependency (which is `public` and in the same package). No import needed since same package.

### 3c. Update `ZSerialize.kt` and `ZDeserialize.kt`

Change import from `io.zenoh.jni.JNIZBytes.serializeViaJNI` to `io.zenoh.jni.KJNIZBytes.serializeViaJNI` (and equivalently `deserializeViaJNI`).

Both `zSerialize` and `zDeserialize` are `inline reified` functions. Because `KJNIZBytes` is `public` in the runtime, it is directly accessible from zenoh-kotlin's `ZSerialize.kt` / `ZDeserialize.kt` with a plain import — `@PublishedApi` is not required.

---

## Phase 4: Scout Migration in `Zenoh.kt`

The local `JNIScout.kt` is deleted (Phase 3a). `Zenoh.kt` must call the runtime's `JNIScout` API.

Runtime signature (from zenoh-jni-runtime `JNIScout.kt`):
```kotlin
fun scout(whatAmI: Int, callback: JNIScoutCallback, onClose: JNIOnCloseCallback, config: JNIConfig?): JNIScout
```

For each `scout()` overload in `Zenoh.kt`:

1. Convert `Set<WhatAmI>` to a bitmask Int:
   ```kotlin
   val bitmask = whatAmI.map { it.value }.reduce { acc, v -> acc or v }
   ```

2. Assemble `JNIScoutCallback` (import `io.zenoh.jni.callbacks.JNIScoutCallback` from runtime):
   ```kotlin
   val scoutCallback = JNIScoutCallback { whatAmI2, id, locators ->
       callback.run(Hello(WhatAmI.fromInt(whatAmI2), ZenohId(id), locators))
   }
   ```

3. Call runtime's `JNIScout.scout()` and wrap result:
   ```kotlin
   runCatching {
       val jniScout = JNIScout.scout(bitmask, scoutCallback, onClose, config?.jniConfig)
       Scout(receiver, jniScout)
   }
   ```

The `Scout<R>` class holds `private var jniScout: JNIScout?`. After deleting the local `JNIScout.kt`, the import resolves to the runtime's public class — no change to `Scout.kt` itself.

---

## Phase 5: Migrate `Config.kt`

The `Config` class stores `internal val jniConfig: JNIConfig` — the field type is unchanged but now resolves to the runtime's public class. Map all static factory calls:

| Old call | New call |
|----------|----------|
| `JNIConfig.loadDefaultConfig()` | `Config(JNIConfig.loadDefault())` |
| `JNIConfig.loadConfigFile(path)` | `runCatching { Config(JNIConfig.loadFromFile(path.toString())) }` |
| `JNIConfig.loadJsonConfig(raw)` | `runCatching { Config(JNIConfig.loadFromJson(raw)) }` |
| `JNIConfig.loadJson5Config(raw)` | `runCatching { Config(JNIConfig.loadFromJson(raw)) }` — runtime's Rust uses `json5::Deserializer` which parses both JSON and JSON5; behavior is preserved despite the method name change |
| `JNIConfig.loadYamlConfig(raw)` | `runCatching { Config(JNIConfig.loadFromYaml(raw)) }` |
| `jniConfig.getJson(key)` → `Result` | `runCatching { jniConfig.getJson(key) }` (runtime throws `ZError`) |
| `jniConfig.insertJson5(key, value)` → `Result` | `runCatching { jniConfig.insertJson5(key, value) }` (runtime throws `ZError`) |

---

## Phase 6: Migrate `Session.kt`

### Session open

Old: `jniSession = JNISession(); jniSession?.open(config)?.getOrThrow()`  
New: `jniSession = JNISession.open(config.jniConfig)`

The runtime's `JNISession` holds a plain `Long sessionPtr` (not `AtomicLong`). Replace all `jniSession.sessionPtr.get()` with `jniSession.sessionPtr`.

For every session method (declarePublisher, declareSubscriber, declareQueryable, etc.) that previously called the local JNI adapter wrappers, inline the primitive extraction and delegate directly to `jniSession.*` runtime methods. Reference zenoh-java's `Session.kt` (in the task-68 workspace) for the exact primitive extraction patterns.

### Liveliness (methods now on JNISession directly, not via JNILiveliness)

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

## Phase 8: Migrate Domain Classes

### `Logger.kt`
Replace `external fun startLogsViaJNI(filter: String)` local declaration with a call to `JNILogger.startLogs(filter)` from the runtime. Remove the local `external` declaration.

### `Publisher.kt`
Inline primitive extraction before calling runtime's `JNIPublisher`:
- `put(payload, encoding, attachment)` → extract `resolvedPayload.bytes`, `resolvedEncoding.id`, `resolvedEncoding.schema`, `attachment?.into()?.bytes`
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
Inline `JNIGetCallback` assembly, then call `jniQuerier.get(keyExpr.jniKeyExpr, keyExpr.keyExpr, params, encoding, payload, timeout, target, consolidation, attachment, onClose, getCallback)`.

---

## Phase 9: Delete Rust Crate

Delete the entire `zenoh-jni/` directory from zenoh-kotlin repository:
- `zenoh-jni/Cargo.toml`
- `zenoh-jni/Cargo.lock`
- `zenoh-jni/src/`
- `zenoh-jni/.cargo/`
- All other files under `zenoh-jni/`

Also delete `rust-toolchain.toml` from the repository root (no longer needed).

---

## Phase 10: Update Documentation and README

- Update `README.md` to remove references to "local Rust build" or `cargo` steps for development setup. Update to describe adding zenoh-java as a submodule and using the composite build.
- Update build/development instructions to reference `zenoh-java/zenoh-jni` as the native library source.

---

## Publication Sequencing Requirement

When zenoh-kotlin's CI runs `publish-jvm.yml` or `publish-android.yml` with `-PremotePublication=true`, Gradle resolves `zenoh-jni-runtime` from Maven Central (the composite build is absent). This means:

1. **zenoh-jni-runtime must be published to Maven Central BEFORE zenoh-kotlin can do a remote publication.**
2. The release process requires: release zenoh-java (which publishes zenoh-jni-runtime) → then release zenoh-kotlin.
3. This sequencing should be noted in the release documentation or CI pipeline ordering.

---

## Publication Architecture Summary

| Scenario | Where native libs live | zenoh-kotlin's JVM/Android artifact |
|---|---|---|
| Local development | `zenoh-java/zenoh-jni/target/debug` (built via composite build) | Local `.so`/`.dylib` in resources (jvmMain local-only wiring) |
| Remote publication (Maven) | `zenoh-jni-runtime` JAR (published by zenoh-java release) | Zero native libs — pure Kotlin wrapper |
| End user runtime | `zenoh-jni-runtime` JAR (pulled as transitive dep by Maven) | `ZenohLoad` in zenoh-jni-runtime handles loading from its own JAR |

This is a clean separation: zenoh-kotlin becomes a pure Kotlin library; all native-level concerns are owned by zenoh-jni-runtime.

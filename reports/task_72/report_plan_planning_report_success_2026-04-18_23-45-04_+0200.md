# Plan: Make zenoh-kotlin Depend on zenoh-jni-runtime

## Context

zenoh-kotlin currently builds its own native JNI library (`zenoh-jni/` Rust crate) and a set of Kotlin adapter classes (`io.zenoh.jni.*`). PR #466 in zenoh-java extracts this JNI layer into `zenoh-jni-runtime` (Maven: `org.eclipse.zenoh:zenoh-jni-runtime`). This plan migrates zenoh-kotlin to consume that shared library, eliminating all Rust code from zenoh-kotlin.

**Key design decisions:**
- zenoh-kotlin's `io.zenoh.jni.*` class names conflict with zenoh-jni-runtime's. They cannot coexist on the classpath. Strategy: delete zenoh-kotlin's JNI classes; migrate adapter logic (domain object construction) into existing higher-level classes.
- Three specific issues from prior adversarial review are addressed explicitly below (serialization source-set mismatch, isRemotePublication scope, JNILiveliness migration).
- Submodule/composite build gated behind file existence to protect ordinary clones and current CI.

**Chosen analog:** The way zenoh-jni-runtime itself structures its `JNISession` adapter is the reference pattern — domain adapter logic lives alongside the JNI class that holds the session pointer.

---

## Phase 0: Verify API Compatibility (Critical First Step)

Before any code changes, confirm against zenoh-java `common-jni` branch:

1. All 16 zenoh-kotlin JNI adapter class names match zenoh-jni-runtime's `commonMain` class names.
2. `JNIZBytesKotlin` (in zenoh-jni-runtime's `jvmAndAndroidMain`) covers the same types as zenoh-kotlin's `JNIZBytes`.
3. zenoh-jni-runtime's `JNISession` exposes `declareLivelinessTokenViaJNI`, `declareLivelinessSubscriberViaJNI`, `livelinessGetViaJNI` methods (replacing zenoh-kotlin's `JNILiveliness`).
4. zenoh-jni-runtime provides `ZenohLoad` (expect/actual) for both JVM and Android.
5. **If any capability gap is found, stop immediately and report failure.**

---

## Phase 1: Add zenoh-java as Git Submodule

Add zenoh-java submodule at path `zenoh-java`, pinned to the `common-jni` branch (source of zenoh-jni-runtime PR #466).

**Files created:** `.gitmodules`

---

## Phase 2: Update Gradle Build Configuration

### `settings.gradle.kts` (root)
- Remove `:zenoh-jni` from `include()`.
- Add composite build gated behind submodule presence (so ordinary clones without `--recurse-submodules` still build from Maven):
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
- Keep `com.android.tools.build:gradle` (Android target remains in zenoh-kotlin).

### `zenoh-kotlin/build.gradle.kts`
- Add dependency: `commonMain.dependencies { implementation("org.eclipse.zenoh:zenoh-jni-runtime:<version>") }` (version from `version.txt`).
- Remove: `BuildMode` enum, `buildZenohJni` task, `compileKotlinJvm.dependsOn("buildZenohJni")`, `configureCargo()` call and function, `configureAndroid()` NDK/Cargo sections, `tasks.whenObjectAdded { cargoBuild }` block, `tasks.withType<Test> { java.library.path }` block.
- Remove: the `isRemotePublication`-gated `jvmMain` resource source dirs for `../jni-libs` and `../zenoh-jni/target` (lines ~82 and ~187). **Keep** the signing gate `signing { isRequired = isRemotePublication }` (line ~158) — this controls Maven Central publication signing and must not be removed.
- Add `jvmAndAndroidMain` intermediate source set in the kotlin multiplatform target configuration (sits between `commonMain` and `jvmMain`/`androidMain`).

---

## Phase 3: Resolve the Serialization Source-Set Mismatch

**The problem:** zenoh-kotlin's `JNIZBytes.kt` is in `commonMain` and returns `ZBytes` from external JNI. zenoh-jni-runtime's `JNIZBytesKotlin.kt` is in `jvmAndAndroidMain` and returns `ByteArray`. `ZSerialize.kt`/`ZDeserialize.kt` (currently commonMain) call `JNIZBytes` — after deletion of the local class, they cannot reach `JNIZBytesKotlin` from commonMain.

**Solution:**
1. **Delete** `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIZBytes.kt` (same class name as runtime's; external declarations move to runtime).
2. **Move** `ZSerialize.kt` and `ZDeserialize.kt` from `commonMain` to the new `jvmAndAndroidMain` source set (zenoh-kotlin targets only JVM and Android, so no API surface is lost).
3. **Update** both files to call `io.zenoh.jni.JNIZBytesKotlin.serialize(t, typeOf<T>())` (returns `ByteArray`) wrapped in `ZBytes(byteArray)`, and `JNIZBytesKotlin.deserialize(zBytes.bytes, kType)` respectively.

---

## Phase 4: Delete zenoh-kotlin's JNI Classes and Migrate Adapter Logic

Both zenoh-kotlin and zenoh-jni-runtime define classes in `io.zenoh.jni.*` with identical names. They cannot coexist. Delete zenoh-kotlin's versions; migrate their Kotlin-side adapter logic into the domain classes.

### What gets deleted:
- All 16 JNI adapter classes in `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/` (except JNILiveliness — see below).
- All 7 callback interfaces in `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/` — these are identical to zenoh-jni-runtime's; replace all import references.
- `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (ZenohLoad JVM actual — replaced by zenoh-jni-runtime's).
- `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` (ZenohLoad Android actual — replaced by zenoh-jni-runtime's).
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt` (ZenohLoad expect — if zenoh-jni-runtime exports its own public `ZenohLoad`; verify in Phase 0).

### Adapter logic migration:

Each deleted zenoh-kotlin JNI class had two layers:
1. `private external fun` declarations (bridge to Rust symbols) → these are now in zenoh-jni-runtime's classes and accessed via the runtime dependency.
2. Adapter methods (construct domain objects from raw JNI handles) → keep this logic, but inline it into the callers (domain classes), which will call zenoh-jni-runtime's JNI classes directly.

**`Session.kt`** (largest change): replace all `jniSession.declarePublisher(...)` calls with inline calls to the zenoh-jni-runtime `JNISession` methods. The `var jniSession: JNISession?` field type becomes zenoh-jni-runtime's `io.zenoh.jni.JNISession`.

**`Config.kt`**: call zenoh-jni-runtime's `JNIConfig` methods directly.

**`Publisher.kt`, `Subscriber.kt`, `Queryable.kt`, `Query.kt`, `Querier.kt`**: update references from the deleted local JNI classes to zenoh-jni-runtime's equivalents; hold raw `Long` pointers as before.

**`KeyExpr.kt`**: update `JNIKeyExpr` import to zenoh-jni-runtime's version.

### JNILiveliness — keep but refactor:
`JNILiveliness.kt` is not deleted. It has valuable adapter logic (callback construction for Sample, Reply, etc.) that is not provided by zenoh-jni-runtime. Refactoring:
- Remove the `private external fun getViaJNI`, `declareTokenViaJNI`, `declareSubscriberViaJNI` declarations at the bottom (lines ~138–156).
- Update the method bodies to call the equivalent methods on zenoh-jni-runtime's `JNISession` (passed as the `jniSession` parameter): `jniSession.declareLivelinessTokenViaJNI(...)`, `jniSession.declareLivelinessSubscriberViaJNI(...)`, `jniSession.livelinessGetViaJNI(...)`.
- `Liveliness.kt` import of `JNILiveliness` remains valid (no class rename needed).

---

## Phase 5: Remove All Rust Code

- Delete the entire `zenoh-jni/` directory (Rust source, `Cargo.toml`, `Cargo.lock`, `build.rs`).
- Delete `rust-toolchain.toml` at repo root.

---

## Phase 6: Update `examples/build.gradle.kts`

- Remove the `CompileZenohJNI` task that runs `cargo build --manifest-path ../zenoh-jni/Cargo.toml`.
- Remove `-Djava.library.path=../zenoh-jni/target/release` system property from example execution tasks.
- zenoh-jni-runtime's `ZenohLoad` handles native library loading for examples too.

---

## Phase 7: Update CI Workflows

### `.github/workflows/ci.yml`
- Remove: Rust toolchain setup (`rustup show`, `rustfmt`, `clippy`), `cargo fmt`, `cargo clippy`, `cargo test`, `cargo build` steps.
- Add `submodules: recursive` to the `actions/checkout@v4` step so CI initializes the zenoh-java submodule and resolves zenoh-jni-runtime from source.
- Note: Since the composite build uses the submodule source (which itself compiles Rust via `zenoh-java/zenoh-jni`), CI still needs `rustup` — but it belongs to zenoh-java's build. Keep Rust toolchain setup for the composite build, or switch to Maven snapshot resolution once zenoh-java PR #466 is merged.

### `.github/workflows/publish-jvm.yml`
- Remove: 6-platform cross-compilation matrix, all `cargo build` steps, `jni-libs` artifact download/aggregation job.
- Publish step becomes: `./gradlew publish -PremotePublication=true` with no pre-built native artifact.

### `.github/workflows/publish-android.yml`
- Remove: NDK setup (`nttld/setup-ndk`), `rustup target add` steps for Android ABIs, Cargo cross-compilation steps.

---

## Critical Files

| File/Path | Change |
|-----------|--------|
| `.gitmodules` | New — adds zenoh-java at `zenoh-java`, branch `common-jni` |
| `settings.gradle.kts` | Remove `:zenoh-jni`; add gated `includeBuild("zenoh-java")` |
| `build.gradle.kts` (root) | Remove `rust-android-gradle` plugin from buildscript |
| `zenoh-kotlin/build.gradle.kts` | Add zenoh-jni-runtime dep; remove Cargo/Rust tasks; add `jvmAndAndroidMain` source set; keep signing gate; remove native-bundling `isRemotePublication` logic only |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIZBytes.kt` | Delete |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/` (14 adapter classes) | Delete all (except JNILiveliness) |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/` (7 interfaces) | Delete all; update callers' imports to zenoh-jni-runtime's versions |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNILiveliness.kt` | Refactor: remove `private external fun` declarations; update to call runtime `JNISession` methods |
| `zenoh-kotlin/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerialize.kt` | New location (moved from commonMain); call `JNIZBytesKotlin.serialize()` + wrap in `ZBytes` |
| `zenoh-kotlin/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZDeserialize.kt` | New location (moved from commonMain); call `JNIZBytesKotlin.deserialize(zBytes.bytes, kType)` |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt` | Major refactor: all JNI class references become zenoh-jni-runtime types |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Config.kt` | Update to use zenoh-jni-runtime's `JNIConfig` |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/*.kt` | Update JNI class references |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/query/*.kt` | Update JNI class references |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/keyexpr/KeyExpr.kt` | Update `JNIKeyExpr` reference |
| `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` | Delete (ZenohLoad provided by runtime) |
| `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt` | Delete (ZenohLoad provided by runtime) |
| `zenoh-jni/` | Delete entire directory |
| `rust-toolchain.toml` | Delete |
| `examples/build.gradle.kts` | Remove `CompileZenohJNI` task and `java.library.path` references |
| `.github/workflows/ci.yml` | Remove Rust steps; add submodule checkout |
| `.github/workflows/publish-jvm.yml` | Remove cross-compilation matrix and artifact aggregation |
| `.github/workflows/publish-android.yml` | Remove NDK/Cargo steps |

---

## Verification

1. **No Rust in zenoh-kotlin**: `find . -name "*.rs" -o -name "Cargo.toml"` returns nothing outside `zenoh-java/` submodule.
2. **Compilation without local Rust** (submodule initialized): `./gradlew :zenoh-kotlin:compileKotlinJvm` succeeds.
3. **JVM tests**: `./gradlew :zenoh-kotlin:jvmTest` passes (requires a zenoh router).
4. **Android build**: `./gradlew :zenoh-kotlin:assembleRelease` succeeds without NDK.
5. **POM check**: `./gradlew generatePomFileForMavenJvmPublication` — confirm `org.eclipse.zenoh:zenoh-jni-runtime` appears as a runtime dependency.
6. **No classpath duplicates**: `./gradlew :zenoh-kotlin:dependencies --configuration jvmRuntimeClasspath` — confirm no duplicate `io.zenoh.jni.*` class entries.
7. **Examples build**: `./gradlew :examples:shadowJar` builds without any Cargo tasks.
8. **API unchanged**: All public types in `io.zenoh.*` retain existing signatures — `Session`, `Config`, `Publisher`, `Subscriber`, `Querier`, `Queryable`, `Query`, `KeyExpr`, `ZBytes`, `zSerialize`, `zDeserialize`, liveliness API.

# Implementation Plan: Make zenoh-kotlin Based on zenoh-java

## Background and Problem Statement

Both zenoh-kotlin and zenoh-java independently compile ~15 Rust source files against the same `zenoh` crate via JNI. zenoh-kotlin also compiles 4 ext Rust files for advanced publisher/subscriber features. The goal is to eliminate the duplication so zenoh-kotlin uses zenoh-java's compiled native library instead of its own, with the external Kotlin API of zenoh-kotlin remaining unchanged.

Three previous plans failed adversarial review:
- ctx_rec_1: Assumed zenoh-java's Kotlin API is a drop-in replacement (it is NOT — different error handling styles, method signatures, etc.)
- ctx_rec_3: Assumed JNI symbols are identical (they are NOT — `openSessionViaJNI` is a companion object method in zenoh-java vs. instance method in zenoh-kotlin, and advanced symbols are missing from zenoh-java entirely)
- Both previous plans considered a two-library approach (sharing raw Rust `Session*` pointers across independently-compiled dylibs) which is architecturally unsound

## Architecture Decision

**zenoh-kotlin bundles zenoh-java's extended native library; zenoh-java's Kotlin classes never appear on zenoh-kotlin users' runtime classpath.**

This approach:
1. Preserves zenoh-kotlin's complete public API (all Kotlin source unchanged)
2. Uses ONE native library (zenoh-java's extended `libzenoh_jni`) — no cross-library Rust pointer sharing
3. Avoids all classpath/package-name conflicts (zenoh-java.jar is never a runtime dependency)
4. Makes additive-only changes to zenoh-java (existing zenoh-java API stays completely intact)

## Concrete JNI Symbol Analysis

**Symbols zenoh-kotlin needs that zenoh-java currently does NOT export:**

| Missing symbol | Source in zenoh-kotlin |
|---|---|
| `Java_io_zenoh_jni_JNISession_openSessionViaJNI` | `session.rs:63` (instance method) |
| `Java_io_zenoh_jni_JNISession_declareAdvancedPublisherViaJNI` | `session.rs:365` |
| `Java_io_zenoh_jni_JNISession_declareAdvancedSubscriberViaJNI` | `session.rs:240` |
| `Java_io_zenoh_jni_JNIAdvancedPublisher_*` (5 methods) | `ext/advanced_publisher.rs` |
| `Java_io_zenoh_jni_JNIAdvancedSubscriber_*` (5 methods) | `ext/advanced_subscriber.rs` |
| `Java_io_zenoh_jni_JNIMatchingListener_freePtrViaJNI` | `ext/matching_listener.rs` |
| `Java_io_zenoh_jni_JNISampleMissListener_freePtrViaJNI` | `ext/sample_miss_listener.rs` |

**Note on `openSessionViaJNI`:** zenoh-java exports `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI` (companion object), while zenoh-kotlin declares it as an instance method (`Java_io_zenoh_jni_JNISession_openSessionViaJNI`). Adding a compat alias in zenoh-java's Rust is the least-disruptive fix — it avoids refactoring zenoh-kotlin's `JNISession` (which would cascade into `Session.kt` changes).

**All other symbols are already compatible** between the two codebases (same class names, same method names, same instance-method convention).

## Phase 1: Extend zenoh-java's Native Library (Prerequisite)

These are additive-only changes. zenoh-java's existing Kotlin API and existing native exports are untouched.

### 1.1 `zenoh-jni/src/session.rs` — Add 3 new exports

**`Java_io_zenoh_jni_JNISession_openSessionViaJNI`** (compat alias):
```rust
#[no_mangle]
pub unsafe extern "C" fn Java_io_zenoh_jni_JNISession_openSessionViaJNI(
    env: JNIEnv, _class: JClass, config_ptr: *const Config,
) -> *const Session {
    // Identical implementation to the companion version above
    let session = open_session(config_ptr);
    match session {
        Ok(session) => Arc::into_raw(Arc::new(session)),
        Err(err) => { throw_exception!(env, zerror!(err)); null() }
    }
}
```

**`Java_io_zenoh_jni_JNISession_declareAdvancedPublisherViaJNI`**: Copy directly from zenoh-kotlin's `zenoh-jni/src/session.rs` lines 365–490.

**`Java_io_zenoh_jni_JNISession_declareAdvancedSubscriberViaJNI`**: Copy directly from zenoh-kotlin's `zenoh-jni/src/session.rs` lines 240–364.

### 1.2 New Rust helper files in `zenoh-jni/src/`

**`owned_object.rs`**: Copy from zenoh-kotlin's `zenoh-jni/src/owned_object.rs` (the `OwnedObject<T>` utility used by ext code).

**`sample_callback.rs`**: Copy from zenoh-kotlin's `zenoh-jni/src/sample_callback.rs` (the `JNISampleCallback` used by `advanced_subscriber.rs`).

### 1.3 New `zenoh-jni/src/ext/` directory

Copy directly from zenoh-kotlin's `zenoh-jni/src/ext/`:
- `mod.rs`
- `advanced_publisher.rs` (5 JNI exports for `JNIAdvancedPublisher`)
- `advanced_subscriber.rs` (5 JNI exports for `JNIAdvancedSubscriber`)
- `matching_listener.rs` (1 JNI export for `JNIMatchingListener.freePtrViaJNI`)
- `sample_miss_listener.rs` (1 JNI export for `JNISampleMissListener.freePtrViaJNI`)

These files reference `crate::owned_object` and `crate::sample_callback`, which are added in 1.2.

### 1.4 `zenoh-jni/src/lib.rs` — Add 3 module declarations

```rust
mod ext;            // new
mod owned_object;   // new
mod sample_callback; // new
```

### 1.5 `zenoh-jni/Cargo.toml` — No change needed

zenoh-java already has `zenoh-ext` in its default features:
```toml
[features]
default = ["zenoh/default", "zenoh-ext"]
```

### Phase 1 outcome

zenoh-java's `libzenoh_jni.so` now exports every JNI symbol that zenoh-kotlin's Kotlin code calls. zenoh-java's own tests and API remain completely unaffected (additive changes only).

## Phase 2: Update zenoh-kotlin to Use zenoh-java's Library

### 2.1 Kotlin source files — NO CHANGES

All files under `zenoh-kotlin/src/` are completely preserved. Public API unchanged.

`Zenoh.kt` (JVM and Android) — NO CHANGE. The existing `ZenohLoad` object loads `libzenoh_jni` by name, searches the classpath and JAR resources. Since zenoh-kotlin will bundle zenoh-java's `libzenoh_jni` in its JAR resources (replacing its own — see 2.3), loading works identically.

### 2.2 Delete zenoh-kotlin's Rust crate

Delete the entire `zenoh-jni/` directory (22 Rust source files, `Cargo.toml`, `Cargo.lock`, `build.rs`).

Delete `rust-toolchain.toml` (Rust toolchain pinning no longer needed in zenoh-kotlin).

### 2.3 Update `zenoh-kotlin/build.gradle.kts` — Replace Rust build with artifact extraction

**Remove:**
- `buildZenohJni` task registration
- `buildZenohJNI()` helper function
- `BuildMode` enum
- `tasks.named("compileKotlinJvm") { dependsOn("buildZenohJni") }` 
- `tasks.whenObjectAdded { ... cargoBuild ... }` (Android cargo build trigger)
- `configureCargo()` function and its `apply(plugin = "...)` call
- `jvmMain { resources.srcDir("../zenoh-jni/target/...") }` — no longer bundling own Rust output
- `jvmTest { resources.srcDir("../zenoh-jni/target/...") }`
- `systemProperty("java.library.path", "../zenoh-jni/target/...")` in test task

**Add** — Two-path native library sourcing (local build vs. published artifact):

```kotlin
// Configuration to resolve zenoh-java's artifact without transitive Kotlin dependencies
val zenohJavaNative by configurations.creating {
    isTransitive = false
}
dependencies {
    zenohJavaNative("org.eclipse.zenoh:zenoh-java-jvm:${version}")
}

// For local development: developers must first build zenoh-java's Rust locally.
// For CI/publication: use the zenoh-java published JAR.
val extractZenohJavaNativeLibs by tasks.registering {
    // Resolve zenoh-java-jvm.jar, extract its {target}/{target}.zip native
    // library resources, place them in build/zenoh-java-native-libs/
    // These are then included as jvmMain resources.
}

jvmMain {
    if (isRemotePublication) {
        resources.srcDir("../jni-libs").include("*/**") // pre-extracted for CI
    } else {
        dependsOn(extractZenohJavaNativeLibs)
        resources.srcDir(extractZenohJavaNativeLibs.outputDir)
    }
}
```

For the local development build path, developers point to a local zenoh-java build via a Gradle property (e.g., `zenohJavaLibDir`), or run the extraction task which pulls from Maven local/remote.

For Android: The `configureCargo()` function is removed. The Cargo build plugin is removed from `apply(plugin = ...)`. The AAR JNI libs are sourced from zenoh-java's Android artifact similarly.

### 2.4 Update `settings.gradle.kts`

Remove `include("zenoh-jni")` (the Rust subproject no longer exists).

Remove the `cargo` plugin from the plugins block (if declared there).

### 2.5 Update `.github/workflows/`

Remove jobs that build Rust targets for zenoh-kotlin (cross-compilation for linux-x86_64, linux-aarch64, apple-x86_64, apple-aarch64, windows-x86_64, android targets).

Keep Kotlin build and test jobs. The CI now downloads zenoh-java's published artifact for the native library.

If zenoh-java's published artifact isn't available (e.g., pending release), the CI workflow can build zenoh-java locally first (`cargo build --manifest-path path/to/zenoh-java/zenoh-jni/Cargo.toml`) before building zenoh-kotlin.

## Implementation Order

1. **PR to zenoh-java** (Phase 1): Submit PR with ext Rust additions. Must be merged and artifact published before zenoh-kotlin CI can use it.
2. **Local validation**: Build zenoh-java locally with Phase 1 changes, extract the `.so`, test it with zenoh-kotlin's test suite.
3. **PR to zenoh-kotlin** (Phase 2): Remove Rust, update build, CI passes using zenoh-java's artifact.

## Files Changed Summary

### zenoh-java repo (Phase 1)
| File | Change |
|------|--------|
| `zenoh-jni/src/session.rs` | Add 3 new `#[no_mangle] pub extern "C"` functions |
| `zenoh-jni/src/owned_object.rs` | New (copy from zenoh-kotlin) |
| `zenoh-jni/src/sample_callback.rs` | New (copy from zenoh-kotlin) |
| `zenoh-jni/src/ext/mod.rs` | New |
| `zenoh-jni/src/ext/advanced_publisher.rs` | New (copy from zenoh-kotlin) |
| `zenoh-jni/src/ext/advanced_subscriber.rs` | New (copy from zenoh-kotlin) |
| `zenoh-jni/src/ext/matching_listener.rs` | New (copy from zenoh-kotlin) |
| `zenoh-jni/src/ext/sample_miss_listener.rs` | New (copy from zenoh-kotlin) |
| `zenoh-jni/src/lib.rs` | Add `mod ext`, `mod owned_object`, `mod sample_callback` |

### zenoh-kotlin repo (Phase 2)
| File | Change |
|------|--------|
| `zenoh-kotlin/build.gradle.kts` | Remove Rust tasks, add zenoh-java artifact extraction |
| `settings.gradle.kts` | Remove `include("zenoh-jni")` |
| `rust-toolchain.toml` | Delete |
| `zenoh-jni/` | Delete entire directory |
| `zenoh-kotlin/src/` | **UNCHANGED** (all Kotlin source) |
| `.github/workflows/` | Remove Rust cross-compilation steps |

## Why This Approach Addresses All Previous Blockers

**vs. ctx_rec_2 (API incompatibility):** We never touch zenoh-kotlin's Kotlin API. zenoh-java's Kotlin classes never appear on zenoh-kotlin's classpath. No package/class conflicts.

**vs. ctx_rec_4 (JNI symbols not identical; cross-library Rust pointers):**
- The one mismatched symbol (`openSessionViaJNI`) is resolved by adding a compat alias in zenoh-java's Rust with identical implementation. No zenoh-kotlin Kotlin changes needed.
- There is ONE native library at runtime. All JNI calls — both "base" calls from zenoh-kotlin's JNI adapters AND "ext" calls — go to the same `libzenoh_jni`. The `Arc<Session>` pointer is created and consumed entirely within that single library. No cross-library Rust object boundary.

**vs. cross-library pointer concern:** By including zenoh-java's entire `libzenoh_jni` (including ext additions) as a single native library in zenoh-kotlin's JAR, there is no two-library design. The concern is completely eliminated.

## Verification Checklist

1. `cargo build --manifest-path zenoh-java/zenoh-jni/Cargo.toml` succeeds with new ext code
2. `nm -D libzenoh_jni.so | grep Java_io_zenoh_jni_JNISession_openSessionViaJNI` shows instance-method symbol
3. `nm -D libzenoh_jni.so | grep Advanced` shows all advanced publisher/subscriber symbols
4. `./gradlew :zenoh-kotlin:jvmTest` — all existing tests pass
5. Run `ZPub` + `ZSub` examples end-to-end (base features via zenoh-java's Rust)
6. Run `ZAdvancedPublisher` + `ZAdvancedSubscriber` examples (ext features via zenoh-java's extended Rust)
7. zenoh-kotlin's JAR resources contain `libzenoh_jni` (sourced from zenoh-java)
8. zenoh-kotlin's JAR does NOT contain any Rust build artifacts from its own `zenoh-jni/` (deleted)
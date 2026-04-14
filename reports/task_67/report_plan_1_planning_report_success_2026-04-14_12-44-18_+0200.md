# Plan: Make zenoh-kotlin Based on zenoh-java

## Why Previous Plans Were Rejected

- Plan 1 (ctx_rec_1): Deleted zenoh-kotlin's Kotlin API and tried to substitute zenoh-java's — wrong, the two Kotlin APIs differ in signatures/return types.
- Plan 2 (ctx_rec_3): Claimed all JNI symbols were identical between the two projects — wrong, at least `openSessionViaJNI` differs (instance method in zenoh-kotlin → `Java_io_zenoh_jni_JNISession_openSessionViaJNI` vs companion object in zenoh-java → `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI`).

## What is Now Known (From Direct Code Inspection)

Both repos were inspected. zenoh-kotlin's JNI Kotlin files vs zenoh-java's Rust exports:

| JNI class | zenoh-kotlin | zenoh-java | Match? |
|---|---|---|---|
| JNISession.openSessionViaJNI | instance method | companion object | **MISMATCH** |
| JNISession (all other methods) | instance method | instance method | ✓ |
| JNIConfig | companion object | companion object | ✓ |
| JNIKeyExpr | companion + instance freePtrViaJNI | companion + instance freePtrViaJNI | ✓ |
| JNIPublisher | instance methods | instance methods | ✓ |
| JNILivelinessToken.undeclareViaJNI | companion object | companion object | ✓ |
| JNIScout | companion object | companion object | ✓ |
| JNILiveliness | singleton object | singleton object | ✓ |
| JNIZBytes | singleton object | singleton object | ✓ |
| JNIAdvancedPublisher/Subscriber/MatchingListener/SampleMissListener | instance methods | **ABSENT** | Missing |

Advanced publisher/subscriber (5 Kotlin JNI adapter classes + their Rust backends) exist only in zenoh-kotlin; zenoh-java has no equivalent.

Note: zenoh-java's config.rs appears to expose fewer methods than zenoh-kotlin's JNIConfig expects — requires full audit to confirm.

## Correct Architecture

Preserve ALL of zenoh-kotlin's public Kotlin API and ALL JNI Kotlin adapter classes unchanged. Extend zenoh-java's Rust crate to export every JNI symbol zenoh-kotlin's adapters call. Make zenoh-kotlin load zenoh-java's single extended native library. Delete zenoh-kotlin's own Rust crate.

Key benefits:
- Single native dylib — no cross-dylib raw Rust pointer sharing
- Both public APIs (zenoh-kotlin and zenoh-java) preserved
- zenoh-kotlin's external interface completely unchanged

---

## Phase 1: Extend zenoh-java's native library

### Step 1.1: Full symbol audit (first action)

Before writing any code, run in both repos:
```
grep -rn "external fun" zenoh-*/src/ --include="*.kt"
grep -rn "pub unsafe extern" zenoh-jni/src/ --include="*.rs"
```
Produce a complete mismatch table. The confirmed mismatch is `openSessionViaJNI`; verify there are no others, and confirm all config exports are present.

### Step 1.2: Add advanced publisher/subscriber Rust code to zenoh-java

Copy from zenoh-kotlin's `zenoh-jni/src/ext/` to zenoh-java's `zenoh-jni/src/ext/`:
- `advanced_publisher.rs` (exports `Java_io_zenoh_jni_JNIAdvancedPublisher_*`, including `Java_io_zenoh_jni_JNIMatchingListener_freePtrViaJNI`)
- `advanced_subscriber.rs` (exports `Java_io_zenoh_jni_JNIAdvancedSubscriber_*`, including `Java_io_zenoh_jni_JNISampleMissListener_freePtrViaJNI`)

Verify shared utilities (`owned_object.rs`, `sample_callback.rs`) are compatible between projects; copy zenoh-kotlin's versions if needed.

Add `#[cfg(feature = "zenoh-ext")] mod ext;` to zenoh-java's `zenoh-jni/src/lib.rs`. The `zenoh-ext` feature is already enabled in zenoh-java's `Cargo.toml`.

### Step 1.3: Add compatibility export for openSessionViaJNI

In zenoh-java's `zenoh-jni/src/session.rs`, add:

```rust
/// Compatibility alias for zenoh-kotlin: its JNISession.openSessionViaJNI is an
/// instance method (no $Companion in the JNI symbol name).
#[no_mangle]
pub unsafe extern "C" fn Java_io_zenoh_jni_JNISession_openSessionViaJNI(
    env: JNIEnv, class: JClass, config_ptr: *const Config,
) -> *const Session {
    Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI(env, class, config_ptr)
}
```

Add any additional compat aliases found in the Step 1.1 audit.

### Step 1.4: Add missing config exports (if confirmed by audit)

If the audit shows zenoh-java's `config.rs` is missing `loadDefaultConfigViaJNI`, `loadConfigFileViaJNI`, `loadJsonConfigViaJNI`, `loadYamlConfigViaJNI`, or `getIdViaJNI`, locate them in zenoh-java (they may be in a different file) or add them.

---

## Phase 2: Update zenoh-kotlin

### Step 2.1: Add zenoh-java as Gradle dependency

In `zenoh-kotlin/build.gradle.kts`:
```kotlin
// JVM
api("org.eclipse.zenoh:zenoh-java-jvm:<version>")
// Android (if android target enabled)
api("org.eclipse.zenoh:zenoh-java-android:<version>")
```
Use `api` so zenoh-java's native library JAR is on the transitive classpath for zenoh-kotlin users.

Confirm exact Maven coordinates from zenoh-java's published POM.

### Step 2.2: Verify/update native library loading in Zenoh.kt

`zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt`:

The existing `ZenohLoad` object loads a library named `zenoh_jni` via:
1. Local filesystem (`libzenoh_jni.{so,dylib,dll}` on classpath)
2. JAR resource at `$target/$target.zip`

If zenoh-java packages its native library using the same `$target/$target.zip` resource convention, the existing `ZenohLoad` code works unchanged once zenoh-java is a classpath dependency — it will find and load the library from zenoh-java's JAR. Verify this.

For local development (`jvmTest` resource path in `build.gradle.kts`): change `resources.srcDir("../zenoh-jni/target/$buildMode")` to point at zenoh-java's local build output, or reference a locally-published zenoh-java artifact.

Apply the same to `zenoh-kotlin/src/androidMain/kotlin/io/zenoh/Zenoh.kt`.

### Step 2.3: Remove zenoh-kotlin's Rust crate

Delete `zenoh-jni/` directory entirely. Remove from `settings.gradle.kts` any include for `zenoh-jni`. Remove all Cargo/Rust task references from build files.

### Step 2.4: Update CI/CD

In `.github/workflows/`: remove Rust toolchain, Cargo build/test, and cross-compilation steps for zenoh-kotlin. Tests will resolve zenoh-java artifact via Gradle (Maven artifact download).

---

## Files to Modify in zenoh-java

| File | Change |
|---|---|
| `zenoh-jni/src/lib.rs` | Add `#[cfg(feature = "zenoh-ext")] mod ext;` |
| `zenoh-jni/src/session.rs` | Add `Java_io_zenoh_jni_JNISession_openSessionViaJNI` compat alias + any others from audit |
| NEW `zenoh-jni/src/ext/advanced_publisher.rs` | Copied + adapted from zenoh-kotlin |
| NEW `zenoh-jni/src/ext/advanced_subscriber.rs` | Copied + adapted from zenoh-kotlin |
| `zenoh-jni/src/config.rs` | Add missing export wrappers if audit confirms gaps |

## Files to Modify in zenoh-kotlin

| File | Change |
|---|---|
| `zenoh-kotlin/build.gradle.kts` | Add zenoh-java `api` dep; update test resource path; remove Cargo tasks |
| `settings.gradle.kts` | Remove `zenoh-jni` include |
| `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` | Verify library loading works; update if resource path differs |
| `zenoh-kotlin/src/androidMain/kotlin/io/zenoh/Zenoh.kt` | Same |
| `.github/workflows/*.yml` | Remove Rust build/cross-compilation steps |

## Files to Delete in zenoh-kotlin

- `zenoh-jni/` — entire Rust crate directory

## Files Unchanged in zenoh-kotlin

- ALL public API Kotlin: `Session.kt`, `Publisher.kt`, `Config.kt`, `Zenoh.kt` (public parts), etc.
- ALL JNI adapter Kotlin: `JNISession.kt`, `JNIAdvancedPublisher.kt`, `JNIConfig.kt`, etc.
- ALL types under `io.zenoh.ext.*`, `io.zenoh.pubsub.*`, `io.zenoh.query.*`, etc.

---

## Verification

1. `./gradlew :zenoh-kotlin:jvmTest` — all existing tests pass
2. `./gradlew :zenoh-java:jvmTest` — zenoh-java tests unaffected (regression check)
3. Examples: `ZPub` + `ZSub` communicate end-to-end through zenoh-java's library
4. Advanced examples: `ZAdvancedPub` + `ZAdvancedSub` work through the moved ext Rust code
5. Cargo does NOT run as part of `./gradlew :zenoh-kotlin:build`
6. zenoh-kotlin JAR contains no `libzenoh_jni.*` resource; native library comes from zenoh-java dependency JAR at runtime

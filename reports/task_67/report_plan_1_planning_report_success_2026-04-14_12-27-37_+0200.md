# Plan: Make zenoh-kotlin Based on zenoh-java

## Context

zenoh-kotlin and zenoh-java are sibling projects that both wrap the same Rust zenoh crate via JNI. The duplication to eliminate is in the **Rust/JNI layer**: both projects independently compile the same base Rust code (`session.rs`, `publisher.rs`, etc.). The goal is to have zenoh-kotlin use zenoh-java's compiled native library for base features, keeping only ext-specific Rust code in zenoh-kotlin.

Previous plan (ctx_rec_1) was rejected (ctx_rec_2) because it assumed zenoh-java's public Kotlin API was a drop-in replacement for zenoh-kotlin's. This revised plan takes the opposite approach: preserve all of zenoh-kotlin's Kotlin code and only replace the underlying native library.

## Key Finding: JNI Signatures Are Identical

After direct code comparison, both projects declare **byte-for-byte identical** `external fun` signatures in their JNI adapter classes:

- `io.zenoh.jni.JNISession.declarePublisherViaJNI(keyExprPtr, keyExprString, sessionPtr, congestionControl, priority, express, reliability)` — **identical**
- `io.zenoh.jni.JNISession.declareSubscriberViaJNI(5 params)` — **identical**
- `io.zenoh.jni.JNISession.declareQueryableViaJNI(6 params)` — **identical**
- `io.zenoh.jni.JNISession.declareQuerierViaJNI(10 params)` — **identical**
- `io.zenoh.jni.JNIPublisher.putViaJNI`, `deleteViaJNI`, `freePtrViaJNI` — **identical**

JNI function names are derived as `Java_{package}_{class}_{method}`. Since both use the same `io.zenoh.jni` package and class names, zenoh-kotlin's JNI adapters will work with zenoh-java's native library **with zero changes** to the Kotlin adapter layer.

## Target Architecture

```
zenoh-kotlin public API (unchanged)
       ↓
zenoh-kotlin JNI adapters (unchanged, same external fun signatures)
       ↙                       ↘
libzenoh_jni.so             libzenoh_kotlin_ext.so
(zenoh-java's library)      (zenoh-kotlin's, ext-only)
base features only          AdvancedPublisher/Subscriber only
       ↑                           ↑
  Same Arc<Session> ptr ──────────┘
  (cross-library, must use same zenoh crate version)
```

## Why This Is Sound

The adversarial review (ctx_rec_2) correctly identified that zenoh-java is NOT a drop-in API replacement. This plan sidesteps that entirely:
- zenoh-kotlin's public API (`Session`, `Publisher`, `Subscriber`, etc. with `Result<T>` style) is **never touched**
- zenoh-kotlin's JNI adapter layer (the `external fun` bridge to native) is **never touched**
- Only the underlying native `.so` file changes — from zenoh-kotlin's own build to zenoh-java's

The cross-library session pointer (ext features needing a session pointer created by zenoh-java's library) is safe because: both libs run in the same JVM process, same heap, and must use the same `zenoh` crate version (same-team release synchronization already enforces this).

## Implementation Steps

### Step 1: Add zenoh-java as Gradle dependency

**File:** `zenoh-kotlin/build.gradle.kts`

- Add `api("org.eclipse.zenoh:zenoh-java-jvm:${version}")` for JVM target
- Add `api("org.eclipse.zenoh:zenoh-java-android:${version}")` for Android target
- Use `api` (not `implementation`) so zenoh-java's native library is on the transitive classpath for users
- Confirm exact Maven coordinates and version string format from zenoh-java's published artifacts

### Step 2: Modify native library loading

**Files:** `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (the `ZenohLoad` object)

The current `ZenohLoad` loads `zenoh_jni`. After migration it must load TWO libraries:
1. `zenoh_jni` — from zenoh-java's JAR resource (existing classpath extraction mechanism will find it in the dependency JAR)
2. `zenoh_kotlin_ext` — from zenoh-kotlin's own JAR resource

The existing `findLibraryStream` + `loadZenohJNI` mechanism searches all classloaders, so it will find resources in dependency JARs. The `{target}/{target}.zip` resource path format must match what zenoh-java uses — verify during implementation.

**File:** `zenoh-kotlin/src/androidMain/kotlin/io/zenoh/Zenoh.kt`

Same change: load both `zenoh_jni` (from zenoh-java's AAR) and `zenoh_kotlin_ext`.

### Step 3: Rename and strip Rust crate to ext-only

**File:** `zenoh-jni/Cargo.toml`

- Change `[lib] name = "zenoh_jni"` → `name = "zenoh_kotlin_ext"`
- Remove dependencies only used by base modules: `json5`, `serde_yaml`, `clap`, `android-logd-logger` (verify by checking remaining imports after deletion)
- Keep: `jni`, `zenoh`, `zenoh-ext`, `async-std`, `tracing`, `flume`

**File:** `zenoh-jni/src/lib.rs`

Remove all base module declarations and keep only:
```
mod errors        (used by ext code)
mod ext           (the advanced features)
mod owned_object  (used by ext code)
mod sample_callback  (used by advanced_subscriber)
mod utils         (used by ext code)
mod zbytes        (already feature-gated for zenoh-ext)
```

### Step 4: Delete base Rust source files

Delete from `zenoh-jni/src/`:
`session.rs`, `publisher.rs`, `subscriber.rs`, `queryable.rs`, `querier.rs`, `query.rs`, `key_expr.rs`, `config.rs`, `zenoh_id.rs`, `liveliness.rs`, `scouting.rs`, `logger.rs`

Keep (used by ext code):
`ext/` directory, `errors.rs`, `utils.rs`, `owned_object.rs`, `sample_callback.rs`, `zbytes.rs`

### Step 5: Update JAR resource bundling

**File:** `zenoh-kotlin/build.gradle.kts`

- Change native resource source to bundle `zenoh_kotlin_ext` (not `zenoh_jni`)
- For local builds: update `resources.srcDir` to point to the renamed library output
- For remote publication: pre-built binaries use new name `libzenoh_kotlin_ext.so`/`.dylib`/`.dll`

### Step 6: Update CI/CD

**Files:** `.github/workflows/`

- Remove cross-compilation for the full `zenoh_jni` Rust crate
- Keep cross-compilation only for the ext-only `zenoh_kotlin_ext`
- Add step to pull zenoh-java's native library for integration tests (via Gradle dependency)

## Critical Constraint: Crate Version Synchronization

Both native libs must use the **same version** of the `zenoh` Rust crate. Already the practice; must be documented as a hard build constraint.

## Files Modified

| File | Change |
|------|--------|
| `zenoh-kotlin/build.gradle.kts` | Add zenoh-java deps, update native resource bundling |
| `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` | Load `zenoh_jni` + `zenoh_kotlin_ext` |
| `zenoh-kotlin/src/androidMain/kotlin/io/zenoh/Zenoh.kt` | Same for Android |
| `zenoh-jni/Cargo.toml` | Rename crate to `zenoh_kotlin_ext`, trim deps |
| `zenoh-jni/src/lib.rs` | Remove base module declarations |
| `.github/workflows/*.yml` | Remove base Rust cross-compilation |

## Files Deleted

`zenoh-jni/src/`: `session.rs`, `publisher.rs`, `subscriber.rs`, `queryable.rs`, `querier.rs`, `query.rs`, `key_expr.rs`, `config.rs`, `zenoh_id.rs`, `liveliness.rs`, `scouting.rs`, `logger.rs`

## Files Unchanged

- **All** zenoh-kotlin public API Kotlin files (`Session.kt`, `Publisher.kt`, etc.)
- **All** zenoh-kotlin JNI adapter Kotlin files (same external fun signatures work with new library)
- `zenoh-jni/src/ext/*.rs`, `errors.rs`, `utils.rs`, `owned_object.rs`, `sample_callback.rs`, `zbytes.rs`

## Verification

1. `./gradlew :zenoh-kotlin:jvmTest` — all existing tests pass
2. Run `examples/ZPub` + `ZSub` — base pub/sub via zenoh-java's library
3. Run advanced publisher/subscriber examples — ext features via zenoh-kotlin's ext library
4. Confirm zenoh-kotlin's JAR contains `libzenoh_kotlin_ext.*` but NOT `libzenoh_jni.*`
5. Confirm `libzenoh_jni.*` at runtime comes from zenoh-java's dependency JAR
6. `cargo build --manifest-path zenoh-jni/Cargo.toml` succeeds with ext-only code

# Plan: Make zenoh-kotlin Based on zenoh-java

## Context

zenoh-kotlin and zenoh-java are parallel projects by the same team (ZettaScale / Eclipse Zenoh). Both independently wrap the same Rust `zenoh` and `zenoh-ext` crates via JNI. The goal is to eliminate the duplicated JNI/Rust layer in zenoh-kotlin by making it depend on zenoh-java for base functionality.

**Current architecture:**
```
zenoh-kotlin public API (io.zenoh.*)
  → zenoh-kotlin JNI adapters (io.zenoh.jni.JNI*)
    → zenoh-kotlin Rust library (zenoh-jni/src/*.rs)
      → Rust zenoh crate
```

**Target architecture:**
```
zenoh-kotlin ext API (io.zenoh.ext.*) + extension functions on Session
  → zenoh-kotlin JNI adapters (ONLY for ext/* features)
    → zenoh-kotlin Rust library (zenoh-jni/src/ext/*.rs ONLY)
      → Rust zenoh-ext crate

zenoh-java public API (io.zenoh.*)
  → zenoh-java JNI adapters (io.zenoh.jni.JNI*)
    → zenoh-java Rust library (libzenoh_jni)
      → Rust zenoh crate
```

## Key Technical Insight: No Package Collision via Class Removal

Both projects use `io.zenoh.*` package namespace with **identical class names** (Session, Config, Publisher, Subscriber, etc.). The package collision problem solves itself: by *removing* zenoh-kotlin's duplicate classes, zenoh-java's classes fill the namespace. **No shading required.**

## Feature Inventory

**In both projects (duplicated — to be removed from zenoh-kotlin):**
- `io.zenoh.Session`, `io.zenoh.Config`, `io.zenoh.Zenoh`, `io.zenoh.ZenohType`
- `io.zenoh.pubsub.Publisher`, `io.zenoh.pubsub.Subscriber`
- `io.zenoh.query.*` (Query, Queryable, Querier, etc.)
- `io.zenoh.keyexpr.*`, `io.zenoh.bytes.*`, `io.zenoh.sample.*`
- `io.zenoh.qos.*`, `io.zenoh.config.*`, `io.zenoh.handlers.*`
- `io.zenoh.liveliness.*`, `io.zenoh.scouting.*`, `io.zenoh.session.*`
- `io.zenoh.annotations.*`, `io.zenoh.exceptions.*`
- JNI adapters (13 classes): JNIConfig, JNISession, JNIPublisher, JNISubscriber, JNIQuery, JNIQueryable, JNIQuerier, JNILiveliness, JNILivelinessToken, JNIScout, JNIKeyExpr, JNIZBytes, JNIZenohId
- JNI callbacks (5 classes): JNISubscriberCallback, JNIGetCallback, JNIQueryableCallback, JNIScoutCallback, JNIOnCloseCallback
- Rust modules (~15 files): config.rs, session.rs, publisher.rs, subscriber.rs, querier.rs, query.rs, queryable.rs, scouting.rs, key_expr.rs, zenoh_id.rs, zbytes.rs, liveliness.rs, logger.rs, sample_callback.rs, utils.rs, owned_object.rs, errors.rs

**Unique to zenoh-kotlin (to keep with JNI):**
- `io.zenoh.ext.*`: AdvancedPublisher, AdvancedSubscriber, MatchingListener, SampleMissListener, CacheConfig, HistoryConfig, RecoveryConfig, MissDetectionConfig, etc.
- JNI adapters: JNIAdvancedPublisher, JNIAdvancedSubscriber, JNIMatchingListener, JNISampleMissListener
- JNI callbacks: JNIMatchingListenerCallback, JNISampleMissListenerCallback
- Rust modules (4 files): zenoh-jni/src/ext/advanced_publisher.rs, advanced_subscriber.rs, matching_listener.rs, sample_miss_listener.rs

## Critical Challenge: Session Pointer Access for Advanced Features

Advanced features (AdvancedPublisher etc.) need the raw Rust session pointer to call into `zenoh-ext`. Currently this comes from zenoh-kotlin's own `JNISession.sessionPtr: AtomicLong`. After switching base session management to zenoh-java, this pointer lives in zenoh-java's `internal class JNISession { internal var sessionPtr: AtomicLong }` — which is inaccessible from zenoh-kotlin.

**Chosen solution (preferred):** Coordinate with zenoh-java to expose a package-private or internal accessor on Session or JNISession for the raw pointer. Since zenoh-java is a sibling project from the same team, this is feasible.

**Fallback solution (during development):** Use JVM reflection to read `sessionPtr` from zenoh-java's JNISession at runtime. This is fragile but unblocks development while the upstream change is being coordinated.

## Implementation Steps

### Step 0: Prerequisites
- Identify the zenoh-java version matching zenoh-kotlin 1.8.0 (expect `io.zenoh:zenoh-java:1.8.x`)
- Confirm zenoh-java's Maven coordinates: `io.zenoh:zenoh-java-jvm` (JVM) and `io.zenoh:zenoh-java-android` (Android)
- Coordinate with zenoh-java team on exposing session pointer (see challenge above)

### Step 1: Build system changes
**Files:** `settings.gradle.kts`, `zenoh-kotlin/build.gradle.kts`, root `build.gradle.kts`

- Add zenoh-java as `api` dependency (JVM: `zenoh-java-jvm`, Android: `zenoh-java-android`) — `api` ensures it's transitive for zenoh-kotlin users
- Keep `zenoh-jni` in `settings.gradle.kts` (needed for ext features), but strip its build to ext-only
- Remove base Cargo tasks from `zenoh-kotlin/build.gradle.kts`; keep only ext compilation
- Remove dependencies now provided transitively by zenoh-java (e.g., `commons-net`)

### Step 2: Remove native library loading
**Files:** `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt`, `zenoh-kotlin/src/androidMain/kotlin/io/zenoh/Zenoh.kt`

- Replace current native loading (which loads `zenoh_jni`) with a minimal loader for the ext-specific native lib
- Rename the ext native library to `zenoh_kotlin_ext` to avoid conflict with zenoh-java's `zenoh_jni` when both are on the classpath

### Step 3: Delete all duplicated Kotlin source files (~50 files)

Remove from `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/`:
- `Config.kt`, `Logger.kt`, `Session.kt`, `Zenoh.kt`, `ZenohType.kt`
- Entire directories: `annotations/`, `bytes/`, `config/`, `exceptions/`, `handlers/`, `keyexpr/`, `liveliness/`, `pubsub/` (Publisher.kt, Subscriber.kt only), `qos/`, `query/`, `sample/`, `scouting/`, `session/`
- From `jni/`: 13 base JNI adapter files + 5 base callback files

**Keep** in `jni/`: JNIAdvancedPublisher.kt, JNIAdvancedSubscriber.kt, JNIMatchingListener.kt, JNISampleMissListener.kt, callbacks/JNIMatchingListenerCallback.kt, callbacks/JNISampleMissListenerCallback.kt

**Keep** entire `io.zenoh.ext.*` directory.

### Step 4: Add advanced declaration methods as extension functions on Session

**New file:** `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/ext/SessionExt.kt`

Move `declareAdvancedPublisher` and `declareAdvancedSubscriber` from the deleted Session.kt to extension functions on `io.zenoh.Session` (which now comes from zenoh-java):

```kotlin
package io.zenoh.ext

import io.zenoh.Session

fun Session.declareAdvancedPublisher(keyExpr: KeyExpr, ...): Result<AdvancedPublisher> { ... }
fun <R> Session.declareAdvancedSubscriber(keyExpr: KeyExpr, ..., handler: Handler<Sample, R>): Result<AdvancedSubscriber<R>> { ... }
```

These call into the remaining JNI classes with the session pointer obtained from zenoh-java.

### Step 5: Update ext JNI adapter classes for session pointer access

**Files:** `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIAdvanced*.kt`

- Update session pointer acquisition to use zenoh-java's exposed accessor (preferred) or reflection (fallback)
- Update `init { ZenohLoad }` to load `zenoh_kotlin_ext` library (renamed from `zenoh_jni`)

### Step 6: Strip zenoh-jni Rust module to ext-only

**Files:** `zenoh-jni/Cargo.toml`, `zenoh-jni/src/lib.rs`, `zenoh-jni/src/ext/*.rs`

- Remove ~15 base module declarations from `lib.rs`, keep only `mod ext`
- Delete all base `.rs` files; keep `ext/`, plus minimal `errors.rs`, `owned_object.rs`, `utils.rs` if used by ext
- Update `Cargo.toml` library name to `zenoh_kotlin_ext`
- Keep `zenoh-ext` feature enabled; remove base `zenoh` features that are no longer needed

### Step 7: Update examples and CI

- `examples/build.gradle.kts`: Remove Cargo build dependency from examples
- `.github/workflows/`: Remove Rust cross-compilation for base modules; keep for ext
- Examples should work as-is since the API surface is unchanged

## Files to Modify (Critical Path)

| File | Change |
|------|--------|
| `settings.gradle.kts` | Keep zenoh-jni for ext; no structural removal needed |
| `zenoh-kotlin/build.gradle.kts` | Add zenoh-java dep, strip base Cargo tasks |
| `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` | Load `zenoh_kotlin_ext` instead of `zenoh_jni` |
| `zenoh-kotlin/src/androidMain/kotlin/io/zenoh/Zenoh.kt` | Same — `loadLibrary("zenoh_kotlin_ext")` |
| `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIAdvanced*.kt` | Update session ptr access |
| `zenoh-jni/src/lib.rs` | Remove base module declarations |
| `zenoh-jni/Cargo.toml` | Rename crate, strip to ext-only deps |
| NEW: `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/ext/SessionExt.kt` | Extension functions for advanced declarations |

## Files to Delete (Bulk)

~50 Kotlin source files across `commonMain/kotlin/io/zenoh/` (all base classes and their JNI adapters).
~15 Rust source files in `zenoh-jni/src/` (all base Rust modules).

## Why This Approach

- **No shading complexity**: Removing duplicates instead of renaming solves the package collision cleanly
- **Preserves public API**: Same class names, same method signatures — users see no change
- **Minimal Rust footprint**: Only ext/advanced features need Rust code; base features use zenoh-java's Rust
- **Extension functions are idiomatic Kotlin**: `session.declareAdvancedPublisher(...)` works identically from the caller's perspective, whether it's a member function or extension function
- **Preserves binary compatibility** for base features; ext features have same source compatibility (minor ABI change for advanced methods, acceptable for same-team projects)

## Verification

1. `./gradlew :zenoh-kotlin:build` — builds successfully, only ext Rust is compiled
2. `./gradlew :zenoh-kotlin:jvmTest` — all existing tests pass unchanged
3. Manual pub/sub via examples: ZPub + ZSub work end-to-end through zenoh-java's implementation
4. AdvancedPublisher/AdvancedSubscriber examples work through zenoh-kotlin's ext JNI
5. Session info methods (`zid()`, `peersZid()`, `routersZid()`) work via zenoh-java's Session

## Prerequisites / Open Questions

1. **Session pointer exposure**: Must coordinate with zenoh-java to expose an internal accessor on Session for the raw Rust pointer — this is a prerequisite for ext JNI to work
2. **Version alignment**: Confirm which zenoh-java version maps to zenoh-kotlin 1.8.0
3. **Native lib naming**: The ext-only Rust crate must output `libzenoh_kotlin_ext.so` (not `libzenoh_jni.so`) to coexist with zenoh-java's native library

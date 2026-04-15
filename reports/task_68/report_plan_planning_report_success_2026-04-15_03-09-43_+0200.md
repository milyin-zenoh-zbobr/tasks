# Implementation Plan: Create `zenoh-jni-runtime` Module in zenoh-java

## Context

The goal is to make zenoh-kotlin a thin wrapper around zenoh-java's native JNI code, eliminating Rust/JNI duplication. The Rust JNI exports (in `zenoh-jni/src/`) are already complete in the work branch:
- Advanced pub/sub via `ext/advanced_publisher.rs`, `ext/advanced_subscriber.rs`, `ext/matching_listener.rs`, `ext/sample_miss_listener.rs`
- Unified `openSessionViaJNI` symbol (removed `00024Companion` prefix by keeping `@JvmStatic`)
- `declareAdvancedSubscriberViaJNI` and `declareAdvancedPublisherViaJNI` added to session.rs
- zenoh-ext feature enabled in `Cargo.toml`

The remaining work is Kotlin-side: extracting the JNI adapter layer into a new `zenoh-jni-runtime` Gradle subproject that both zenoh-java and zenoh-kotlin can depend on.

**Core constraint**: `zenoh-jni-runtime` must contain **zero** references to `io.zenoh.*` facade types (Config, KeyExpr, Publisher, Sample, Reply, etc.) — only primitives, ByteArray, Long handles, and callback interfaces.

---

## Architecture Overview

```
zenoh-kotlin (future, separate repo)
zenoh-java
    ↓ both depend on
zenoh-jni-runtime   ← new Gradle subproject (this PR)
    ├── io.zenoh.jni.*    (JNI adapters, primitive-only API)
    ├── io.zenoh.jni.callbacks.*  (callback interfaces, already primitive-only)
    └── zenoh-jni/        (Rust crate stays at repo root, runtime owns its build)
```

---

## Step 1: Create `zenoh-jni-runtime` Gradle Subproject

### 1a. `settings.gradle.kts` — add module
```
include(":zenoh-jni-runtime")
```

### 1b. `zenoh-jni-runtime/build.gradle.kts`
Adapted from `zenoh-java/build.gradle.kts`:
- Same multiplatform Kotlin setup (JVM + optional Android targets)
- Owns `buildZenohJni` task pointing to `../zenoh-jni/Cargo.toml`
- JVM resources include the compiled native `.so`/`.dylib`/`.dll` from `../zenoh-jni/target/`
- Published as `org.eclipse.zenoh:zenoh-jni-runtime`
- NO kotlin-serialization, NO guava/commons-net dependencies (those are facade concerns)
- No dokka/examples (runtime is an internal dependency)

### 1c. ZenohLoad — move to `zenoh-jni-runtime`
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/ZenohLoad.kt`: `internal expect object ZenohLoad`
- `zenoh-jni-runtime/src/jvmMain/kotlin/io/zenoh/ZenohLoad.kt`: copy the existing `actual object ZenohLoad` with library loading logic from zenoh-java's `jvmMain/Zenoh.kt`
- `zenoh-jni-runtime/src/androidMain/kotlin/io/zenoh/ZenohLoad.kt`: copy from zenoh-java's androidMain
- In zenoh-java: `ZenohLoad` expect/actual declarations are **removed** from `Zenoh.kt`; references to `ZenohLoad` in facade code are deleted (loading is triggered by the runtime's init block when JNI adapters are first used)

---

## Step 2: Refactor JNI Adapters (move to `zenoh-jni-runtime`)

**Key refactoring principle**: All JNI adapter methods in the runtime take/return only: `Long`, `Int`, `Boolean`, `String`, `ByteArray`, `List<ByteArray>`, and callback interfaces (already primitive-only). No `Config`, `KeyExpr`, `Publisher`, `Sample`, `Reply`, etc.

The `external fun` declarations become **public** in the runtime (zenoh-kotlin needs access from a different module/repo).

### Files moved as-is (already primitive-only):
- `JNIPublisher.kt`, `JNISubscriber.kt`, `JNIQueryable.kt`
- `JNILivelinessToken.kt`, `JNIZBytes.kt`, `JNIZenohId.kt`
- `callbacks/JNISubscriberCallback.kt`, `JNIQueryableCallback.kt`, `JNIGetCallback.kt`, `JNIScoutCallback.kt`, `JNIOnCloseCallback.kt`

Only change: `internal` → `public` visibility; remove `ZenohLoad` import (init block stays, but references runtime's own ZenohLoad).

### Files requiring refactoring:

**`JNISession.kt`** (most complex):
- Remove all high-level wrapper methods: `declarePublisher`, `declareSubscriber*`, `declareQueryable*`, `declareQuerier`, `performGet*`, `performPut`, `performDelete`, `zid`, `peersZid`, `routersZid`, `declareKeyExpr`, `undeclareKeyExpr`
- Keep: `companion object { open(configPtr: Long): JNISession }` (takes `Long`, not `Config`)
- Keep: `close()` → calls `closeSessionViaJNI`
- Make all `external fun` declarations `public` (previously `private`)
- Add new `public external fun` declarations matching the new Rust exports in session.rs:
  - `declareAdvancedSubscriberViaJNI(keyExprPtr, keyExprStr, sessionPtr, historyConfig*, recoveryConfig*, subscriberDetection, callback, onClose): Long`
  - `declareAdvancedPublisherViaJNI(keyExprPtr, keyExprStr, sessionPtr, ...): Long`

**`JNIConfig.kt`**:
- Factory methods return `Long` instead of `Config`:
  - `loadDefaultConfig(): Long`
  - `loadConfigFile(path: String): Long`
  - `loadJsonConfig(rawConfig: String): Long`
  - `loadYamlConfig(rawConfig: String): Long`
- `getJson`, `insertJson5`, `close` — unchanged (already primitive)

**`JNIKeyExpr.kt`**:
- Factory methods return `String` instead of `KeyExpr`:
  - `tryFrom(keyExpr: String): String`
  - `autocanonize(keyExpr: String): String`
  - `join(keyExprPtr: Long, keyExprStr: String, other: String): String`
  - `concat(keyExprPtr: Long, keyExprStr: String, other: String): String`
- Comparison methods take raw `(ptrA: Long, strA: String, ptrB: Long, strB: String)` instead of KeyExpr facades
- `freePtrViaJNI(ptr: Long)` — unchanged

**`JNIQuery.kt`**:
- `replySuccess(sample: Sample)` → `replySuccess(keyExprPtr, keyExprStr, payload, encodingId, encodingSchema, tsEnabled, tsNtp64, attachment, qosExpress)` — exposes the existing external fun directly
- `replyError(error, encoding)` → `replyError(errorBytes: ByteArray, encodingId: Int, encodingSchema: String?)`
- `replyDelete(keyExpr, ts, attachment, qos)` → `replyDelete(keyExprPtr, keyExprStr, tsEnabled, tsNtp64, attachment, qosExpress)`
- `close()` — unchanged

**`JNIQuerier.kt`**:
- `performGet*(keyExpr: KeyExpr, ...)` → take `(keyExprPtr: Long, keyExprStr: String, params: String?, ...)` instead of KeyExpr facade
- Remove Reply construction (moves to zenoh-java's `Querier.kt`)

**`JNIScout.kt`**:
- `scoutWithHandler/Callback(config: Config?, ...)` → take `configPtr: Long` instead of Config
- Return `Long` (raw scout ptr) instead of `HandlerScout`/`CallbackScout` facade objects
- Remove `Hello` construction (moves to zenoh-java's `Zenoh.kt`)

**`JNILiveliness.kt`**:
- All methods take `(keyExprPtr: Long, keyExprStr: String)` instead of `KeyExpr`
- Return `Long` handles instead of facade `LivelinessToken`, `CallbackSubscriber`, `HandlerSubscriber`
- Remove `Reply` construction in `get()` (moves to zenoh-java's `Liveliness.kt`)

### New files in `zenoh-jni-runtime`:

**`JNIAdvancedPublisher.kt`**: Adapter class wrapping `ptr: Long` with external funs matching `Java_io_zenoh_jni_JNIAdvancedPublisher_*` Rust exports:
- `putViaJNI(payload, encodingId, encodingSchema, attachment)`
- `deleteViaJNI(attachment)`
- `declareMatchingListenerViaJNI(callback, onClose): Long`
- `declareBackgroundMatchingListenerViaJNI(callback, onClose)`
- `getMatchingStatusViaJNI(): Boolean`
- `freePtrViaJNI()`

**`JNIAdvancedSubscriber.kt`**: Adapter wrapping `ptr: Long`:
- `declareDetectPublishersSubscriberViaJNI(callback, onClose): Long`
- `declareBackgroundDetectPublishersSubscriberViaJNI(callback, onClose)`
- `declareSampleMissListenerViaJNI(callback, onClose): Long`
- `declareBackgroundSampleMissListenerViaJNI(callback, onClose)`
- `freePtrViaJNI()`

**`JNIMatchingListener.kt`**: `class JNIMatchingListener(val ptr: Long) { external fun freePtrViaJNI() }`

**`JNISampleMissListener.kt`**: `class JNISampleMissListener(val ptr: Long) { external fun freePtrViaJNI() }`

**`callbacks/JNIMatchingListenerCallback.kt`**: `fun interface JNIMatchingListenerCallback { fun run(matching: Boolean) }` (derived from `MatchingStatus::matching()` call in advanced_publisher.rs)

**`callbacks/JNISampleMissListenerCallback.kt`**: Exact signature derived from `ext/advanced_subscriber.rs` miss listener callback invocation parameters.

---

## Step 3: Refactor `zenoh-java` to Use `zenoh-jni-runtime`

### 3a. Build changes (`zenoh-java/build.gradle.kts`):
- Remove `buildZenohJni` task and `buildZenohJNI` function (moved to zenoh-jni-runtime)
- Remove Rust resources from `jvmMain`/`jvmTest` (native lib packaged by zenoh-jni-runtime)
- Add dependency: `implementation(project(":zenoh-jni-runtime"))`
- Keep all other dependencies (commons-net, guava, serialization)
- `jvmArgs("-Djava.library.path=../zenoh-jni/target/$buildMode")` for tests: retained

### 3b. Remove all `io.zenoh.jni.*` files from `zenoh-java/src/` (moved to runtime)

### 3c. Update facade classes to reassemble objects from primitives:

**`Session.kt`**: Add the callback assembly lambdas and facade wrapping that was in JNISession:
- `declarePublisher(...)`: call `jniSession.declarePublisherViaJNI(keyExprPtr, keyExprStr, ...)`, wrap result in `Publisher(keyExpr, ..., JNIPublisher(ptr))`
- `declareSubscriberWithHandler/Callback(...)`: inline the `JNISubscriberCallback { ke, payload, ... -> Sample(...) }` lambda (logic identical to what's currently in JNISession)
- `declareQueryableWith*(...)`: inline the `JNIQueryableCallback { ... -> Query(...) }` assembly
- `declareQuerier(...)`: call `declareQuerierViaJNI(...)`, wrap in `Querier(keyExpr, qos, JNIQuerier(ptr))`
- `performGet*(...)`: inline the `JNIGetCallback { ... -> Reply.Success/Error(...) }` assembly
- `zid()/peersZid()/routersZid()`: call JNI methods and wrap `ByteArray` → `ZenohId`
- `declareKeyExpr/undeclareKeyExpr`: call JNI methods, wrap `Long` → `KeyExpr`

**`Config.kt`**: Factory methods call `JNIConfig.loadDefaultConfig()` (returns `Long`) and wrap: `Config(JNIConfig(ptr))`

**`KeyExpr.kt`**: `tryFrom/autocanonize` call primitive JNI returning `String`, wrap in `KeyExpr(str, null)`; comparison methods extract ptrs/strings from facades

**`Query.kt`**: `replySuccess(sample)` decomposes sample to primitives, calls `jniQuery.replySuccessViaJNI(...)`

**`Zenoh.kt`** (scouting): Pass `configPtr` to `JNIScout.scoutViaJNI`, inline `JNIScoutCallback { whatAmI, id, locators -> Hello(...) }` assembly

**`Liveliness.kt`**: Pass keyExpr as `(ptr, str)` primitives, wrap returned `Long` in `LivelinessToken`/`JNISubscriber`

---

## Critical Files

| File | Change |
|------|--------|
| `settings.gradle.kts` | Add `include(":zenoh-jni-runtime")` |
| `zenoh-jni-runtime/build.gradle.kts` | New (adapted from zenoh-java build) |
| `zenoh-jni-runtime/src/...ZenohLoad.kt` | New (moved from zenoh-java) |
| `zenoh-jni-runtime/src/.../jni/JNISession.kt` | New (heavily refactored, primitive-only) |
| `zenoh-jni-runtime/src/.../jni/JNIConfig.kt` | New (factory methods return Long) |
| `zenoh-jni-runtime/src/.../jni/JNIKeyExpr.kt` | New (factory methods return String) |
| `zenoh-jni-runtime/src/.../jni/JNIQuery.kt` | New (takes primitives not Sample) |
| `zenoh-jni-runtime/src/.../jni/JNIQuerier.kt` | New (takes primitive keyexpr) |
| `zenoh-jni-runtime/src/.../jni/JNIScout.kt` | New (returns Long not facades) |
| `zenoh-jni-runtime/src/.../jni/JNILiveliness.kt` | New (takes primitive keyexpr) |
| `zenoh-jni-runtime/src/.../jni/JNIAdvancedPublisher.kt` | New |
| `zenoh-jni-runtime/src/.../jni/JNIAdvancedSubscriber.kt` | New |
| `zenoh-jni-runtime/src/.../jni/JNIMatchingListener.kt` | New |
| `zenoh-jni-runtime/src/.../jni/JNISampleMissListener.kt` | New |
| `zenoh-jni-runtime/src/.../jni/callbacks/JNIMatchingListenerCallback.kt` | New |
| `zenoh-jni-runtime/src/.../jni/callbacks/JNISampleMissListenerCallback.kt` | New |
| `zenoh-java/build.gradle.kts` | Remove Rust build, add runtime dep |
| `zenoh-java/src/.../Zenoh.kt` | Remove ZenohLoad expect, update scouting |
| `zenoh-java/src/.../Session.kt` | Add facade assembly (moved from JNISession) |
| `zenoh-java/src/.../Config.kt` | Wrap Long → Config |
| `zenoh-java/src/.../keyexpr/KeyExpr.kt` | Wrap String primitives |
| `zenoh-java/src/.../jni/` (all) | **Delete** (moved to runtime) |

---

## Verification

1. `./gradlew :zenoh-jni-runtime:build` — runtime compiles without facade imports
2. `./gradlew :zenoh-java:test` — all existing tests pass
3. `grep -r "io.zenoh\." zenoh-jni-runtime/src/` — should find zero non-jni classes imported
4. `grep -r "ZenohLoad\|System.load" zenoh-java/src/` — zero matches (loading in runtime)
5. Run ZPub/ZSub/ZGet/ZQueryable examples to verify end-to-end functionality
6. Verify `JNIAdvancedPublisher` and `JNIAdvancedSubscriber` Kotlin methods match Rust `Java_io_zenoh_jni_JNIAdvancedPublisher_*` symbols

## Rationale

- **No classpath collision**: runtime uses `io.zenoh.jni.*` exclusively — distinct from `io.zenoh.*` facade namespace
- **Minimal logic change**: callback assembly code is just MOVED from JNISession.kt to Session.kt; identical logic
- **Analog**: same extract-JNI-layer pattern as RocksDB (jni-bindings separate from Java API)
- **Rust stays in place**: the Rust crate at `zenoh-jni/` doesn't need to move; `zenoh-jni-runtime`'s build.gradle.kts references it at `../zenoh-jni/`

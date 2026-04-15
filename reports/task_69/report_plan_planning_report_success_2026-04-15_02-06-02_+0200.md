# Architecture Plan: Make zenoh-kotlin JNI-free by Depending on zenoh-java's JNI Runtime

## Problem Summary

zenoh-kotlin currently compiles its own Rust `zenoh-jni` module (~3,900 LOC) and maintains a complete `io.zenoh.jni.*` Kotlin JNI adapter layer. The goal is to eliminate all native code from zenoh-kotlin and let it delegate to zenoh-java's JNI infrastructure, while keeping zenoh-kotlin's public `io.zenoh.*` API (Result-based, Channel-based) intact.

The previous plan (ctx_rec_1) proposed zenoh-kotlin depending directly on zenoh-java's public `io.zenoh.*` artifact. The adversarial review (ctx_rec_2) correctly identified that this fails because both projects export classes with identical fully-qualified names (`io.zenoh.Session`, `io.zenoh.Config`, `io.zenoh.keyexpr.KeyExpr`, etc.) — putting both on the same runtime classpath causes classloader collisions and broken behavior.

## Correct Architecture: Three-Layer with a Shared JNI Runtime

The solution is to extract the JNI adapter layer into a separately published module with a **distinct package namespace** (`io.zenoh.jni.*`). Both facades depend on this shared module. The user depends on **one** facade — never both.

```
User Code (imports io.zenoh.*)
        ↓
zenoh-kotlin  [pure Kotlin: no external fun, no Rust, no System.loadLibrary]
  - io.zenoh.* (Session, Config, KeyExpr, …) — Result<T>, Channel<T> API
  - Calls JNI adapters from zenoh-jni-runtime
  - Constructs its own Sample, ZBytes, KeyExpr from raw primitives
        ↓               ↓
zenoh-java  [Kotlin + JNI]      zenoh-jni-runtime  [new artifact from zenoh-java repo]
  - io.zenoh.*                    - io.zenoh.jni.*  ← distinct namespace, NO io.zenoh.* types
  - exception-based API           - JNISession (returns raw handles, not facade objects)
  - Constructs its own            - JNIPublisher, JNISubscriber, JNIQueryable, JNIQuerier
    facade objects                - JNIQuery, JNIConfig, JNIKeyExpr, JNIScout
        ↓                         - JNILiveliness, JNILivelinessToken, JNIZBytes, JNIZenohId
        └──────────────────────── - JNIAdvancedPublisher, JNIAdvancedSubscriber (NEW)
                                  - JNIMatchingListener, JNISampleMissListener (NEW)
                                  - JNISubscriberCallback, JNIQueryableCallback,
                                    JNIGetCallback, JNIScoutCallback, JNIOnCloseCallback
                                  - ZenohLoad (native library loading)
                                  - zenoh-jni Rust module (ALL native code)
```

**Why no classpath collision**: `io.zenoh.jni.*` (runtime) and `io.zenoh.*` (facades) are distinct package paths. The runtime module has zero `io.zenoh.*` top-level types. Users import only the facade (`zenoh-kotlin` or `zenoh-java`), not both.

---

## Key Design Constraint: JNI Adapters Must Be Facade-Independent

The central refactoring challenge is that current JNI adapter classes are coupled to facade types. For example:

- `JNIPublisher.put(payload: IntoZBytes, encoding: Encoding?)` — takes facade types  
- `JNIQuery.replySuccess(sample: Sample)` — takes a facade type  
- `JNIScout.scout()` creates `Hello(WhatAmI.fromInt(...), ZenohId(id), ...)` — creates facade objects  
- `JNIConfig.loadDefaultConfig()` returns `Config` — a facade type  
- `JNIKeyExpr.tryFrom()` returns `KeyExpr` — a facade type  

For the shared `zenoh-jni-runtime` module, all of these must be refactored to use **only primitives, `ByteArray`, `List<String>`, and `Long` native handles**. The facade layer (zenoh-java or zenoh-kotlin) then wraps/unwraps these into its own typed objects.

Concretely:
- `JNIPublisher.put(payload, encoding, attachment)` → `put(payloadBytes: ByteArray, encodingId: Int, encodingSchema: String?, attachmentBytes: ByteArray?)`
- `JNIQuery.replySuccess(sample: Sample)` → `replySuccess(keyExprPtr: Long, keyExprStr: String, payloadBytes: ByteArray, encodingId: Int, encodingSchema: String?, tsEnabled: Boolean, tsNtp64: Long, attachmentBytes: ByteArray?, qosExpress: Boolean)`
- `JNIConfig.loadDefaultConfig()` → returns `Long` (config ptr); facade creates `Config` wrapper
- `JNIKeyExpr.tryFrom()` → returns `String` (canonicalized string); facade wraps in `KeyExpr`
- `JNIZenohId` → returns `ByteArray`; facade wraps in `ZenohId`
- `JNIScout` companion → exposes raw `scoutViaJNI(...)` without creating `Hello`; facade's `Zenoh.scout()` creates `Hello` objects in its own `JNIScoutCallback`

This is already how many JNI bridges work in practice: the JNI layer passes bytes, the upper layer constructs typed objects.

**Note**: The `JNISubscriberCallback`, `JNIQueryableCallback`, `JNIGetCallback`, `JNIScoutCallback`, and `JNIOnCloseCallback` interfaces **already use only primitives and ByteArrays** — they require no changes. The callback assembly (converting raw params into `Sample`, `Query`, `Hello`, etc.) happens in the facade, not in the JNI runtime.

---

## Changes Required in zenoh-java Repository

### Step 1: Create new `zenoh-jni-runtime` Gradle subproject

Structure:
```
zenoh-java/
  zenoh-jni-runtime/         ← NEW subproject
    src/commonMain/kotlin/io/zenoh/jni/
      JNISession.kt           (refactored — returns raw handles)
      JNIConfig.kt            (refactored — returns Long ptrs)
      JNIKeyExpr.kt           (refactored — returns String/Boolean)
      JNIPublisher.kt         (refactored — takes raw ByteArrays)
      JNISubscriber.kt        (unchanged — already pure handle)
      JNIQueryable.kt         (unchanged — already pure handle)
      JNIQuerier.kt           (refactored — takes raw params)
      JNIQuery.kt             (refactored — takes raw params instead of Sample/KeyExpr)
      JNIScout.kt             (refactored — no facade object creation)
      JNILiveliness.kt        (refactored — returns Long ptrs)
      JNILivelinessToken.kt   (unchanged)
      JNIZBytes.kt            (unchanged — already ByteArray-based)
      JNIZenohId.kt           (refactored — returns ByteArray)
      ZenohLoad.kt            (native library loading, moved here)
      JNIAdvancedPublisher.kt (NEW — ported from zenoh-kotlin)
      JNIAdvancedSubscriber.kt (NEW — ported from zenoh-kotlin)
      JNIMatchingListener.kt  (NEW — ported from zenoh-kotlin)
      JNISampleMissListener.kt (NEW — ported from zenoh-kotlin)
    src/commonMain/kotlin/io/zenoh/jni/callbacks/
      JNISubscriberCallback.kt    (moved, unchanged)
      JNIQueryableCallback.kt     (moved, unchanged)
      JNIGetCallback.kt           (moved, unchanged)
      JNIScoutCallback.kt         (moved, unchanged)
      JNIOnCloseCallback.kt       (moved, unchanged)
      JNIMatchingListenerCallback.kt (NEW — ported from zenoh-kotlin)
      JNISampleMissListenerCallback.kt (NEW — ported from zenoh-kotlin)
  zenoh-jni/                  ← Rust crate MOVED here (from repo root)
    Cargo.toml                (enable zenoh-ext feature)
    src/
      ext/advanced_publisher.rs   (ported from zenoh-kotlin's zenoh-jni)
      ext/advanced_subscriber.rs  (ported)
      ext/matching_listener.rs    (ported)
      ext/sample_miss_listener.rs (ported)
      ...all existing Rust modules...
  build.gradle.kts            (compiles Rust, packages native lib)
  Published as: org.eclipse.zenoh:zenoh-jni-runtime
```

All classes in this module have `internal` visibility within the module or `public` as needed for both facades to access them. Since zenoh-kotlin and zenoh-java are separate Gradle projects/repos, the classes must be at least **`public`** (but with the clear convention that they are implementation details, not user-facing API).

### Step 2: Refactor zenoh-java to use `zenoh-jni-runtime`

- Remove the existing `io.zenoh.jni.*` Kotlin classes from zenoh-java (they move to `zenoh-jni-runtime`)
- Remove the existing `zenoh-jni/` Rust module from the zenoh-java repo root (it moves to `zenoh-jni-runtime/zenoh-jni/`)
- zenoh-java depends on `zenoh-jni-runtime`
- The facade-object assembly code (converting raw handles/primitives into `Publisher`, `Subscriber`, `Sample`, `Config`, `KeyExpr`, etc.) moves from `JNISession` up to zenoh-java's `Session.kt`  
  - Example: `declarePublisher()` was: `JNISession.declarePublisher()` returns `Publisher`. Now: zenoh-java `Session.declarePublisher()` calls `jniRuntime.JNISession.declarePublisherHandle()` which returns a `JNIPublisher`, then wraps it as `Publisher(keyExpr, ..., jniPub)`
  - Subscriber callback assembly (`JNISubscriberCallback { ... -> Sample(...) }`) moves from `JNISession` to zenoh-java's `Session.kt`
- zenoh-java's public `io.zenoh.*` API remains fully unchanged

### Step 3: Enable zenoh-ext in the Rust module (within `zenoh-jni-runtime`)

In `zenoh-jni-runtime/zenoh-jni/Cargo.toml`:
```toml
[dependencies]
zenoh = { ... }
zenoh-ext = { ... features = ["unstable", "internal"] }
```

Port the Rust JNI functions for advanced pub/sub from zenoh-kotlin's `zenoh-jni/src/ext/`:
- `advanced_publisher.rs`
- `advanced_subscriber.rs`  
- `matching_listener.rs`
- `sample_miss_listener.rs`

The function signatures (`Java_io_zenoh_jni_JNIAdvancedPublisher_...`) remain identical since the package and class names are the same (`io.zenoh.jni.JNIAdvancedPublisher`).

---

## Changes Required in zenoh-kotlin Repository

### Step 1: Remove the entire native/JNI layer

- Delete `zenoh-jni/` directory (entire Rust module — Cargo.toml, src/)
- Delete all `io.zenoh.jni.*` Kotlin source files:
  - `JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt`
  - `JNIConfig.kt`, `JNIKeyExpr.kt`, `JNISession.kt`, `JNIScout.kt`
  - `JNIPublisher.kt`, `JNISubscriber.kt`, `JNIQueryable.kt`, `JNIQuerier.kt`, `JNIQuery.kt`
  - `JNILiveliness.kt`, `JNILivelinessToken.kt`, `JNIMatchingListener.kt`, `JNISampleMissListener.kt`
  - `JNIZBytes.kt`, `JNIZenohId.kt`
  - All `io.zenoh.jni.callbacks.*` files
- Remove `zenoh-jni` from `settings.gradle.kts`
- Remove Rust compilation tasks from `zenoh-kotlin/build.gradle.kts`
- Remove `rust-toolchain.toml` (no longer needed)

### Step 2: Add `zenoh-jni-runtime` dependency

In `zenoh-kotlin/build.gradle.kts`:
```kotlin
commonMainImplementation("org.eclipse.zenoh:zenoh-jni-runtime:<version>")
```

### Step 3: Update Session.kt

The pattern is the same as today, but instead of calling its own `JNISession`, it calls `io.zenoh.jni.JNISession` from the runtime dependency.

- Hold an internal `io.zenoh.jni.JNISession` reference
- `declarePublisher()`: wrap in `runCatching {}`, call runtime's `JNISession.declarePublisher()` which returns `JNIPublisher`; create zenoh-kotlin's `Publisher(keyExpr, qos, encoding, jniPub)` — exactly the same as today
- `declareSubscriber()`: construct `JNISubscriberCallback { ke, payload, encodingId, ... -> val sample = Sample(KeyExpr(ke, null), ZBytes(payload), Encoding(encodingId, encodingSchema), ...) ; callback(sample) }` — same as today, just `JNISubscriberCallback` is imported from the runtime
- `get()`: construct `JNIGetCallback { ... -> val reply = Reply(...) ... }` — same assembly as today
- `declareQueryable()`: construct `JNIQueryableCallback { ... -> val query = Query(...) ... }` — same as today
- For each `runCatching {}` wrapping, the `ZError` exception from JNI propagates into a `Result.failure`

The callback assembly logic in zenoh-kotlin's `Session.kt` is essentially moved FROM zenoh-kotlin's `JNISession.kt` (which is deleted) TO zenoh-kotlin's `Session.kt`. The logic itself doesn't change.

### Step 4: Update Config.kt

```kotlin
// Old: internal class Config(internal val jniConfig: JNIConfig)  ← uses zenoh-kotlin's JNIConfig
// New: internal class Config(internal val configPtr: Long)   ← uses raw ptr from runtime's JNIConfig
```

Or simpler: keep the same structure but with `JNIConfig` imported from `io.zenoh.jni.JNIConfig` (the runtime). Calls to `JNIConfig.loadDefaultConfig()` now return a `Long` ptr; Config wraps it.

### Step 5: Update KeyExpr.kt, Zenoh.kt, Logger.kt, Liveliness.kt

- `KeyExpr.kt`: `JNIKeyExpr.tryFrom()` now returns a `String` from the runtime; `KeyExpr` is constructed the same as before
- `Zenoh.kt` (scout): construct `JNIScoutCallback { whatAmI, id, locators -> callback(Hello(WhatAmI.fromInt(whatAmI), ZenohId(id), locators)) }` — same logic, just `JNIScoutCallback` comes from runtime
- `Logger.kt`: `JNILogger` (which declares `external fun startLogsViaJNI`) is deleted; the logger functionality will need to be exposed via the runtime's JNI logging function (same pattern — one additional item to add to the runtime)
- `Liveliness.kt`: use `JNILiveliness` from the runtime (which now returns raw handles)

### Step 6: Update AdvancedPublisher.kt and AdvancedSubscriber.kt

These now use `JNIAdvancedPublisher` and `JNIAdvancedSubscriber` from the runtime instead of from zenoh-kotlin's own JNI layer. The public API and the internal logic are unchanged — only the import source changes.

### Step 7: Keep all Kotlin-specific additions

These are unchanged and remain in zenoh-kotlin:
- `ChannelHandler.kt`, `MatchingChannelHandler.kt`, `SampleMissChannelHandler.kt`
- `AdvancedPublisher.kt`, `AdvancedSubscriber.kt` (public API)
- `ext/CacheConfig.kt`, `ext/HistoryConfig.kt`, `ext/RecoveryConfig.kt`, `ext/MissDetectionConfig.kt`
- All handler interfaces
- `ext/ZSerialize.kt`, `ext/ZDeserialize.kt` (use runtime's `JNIZBytes` via import)

---

## Rationale for This Approach

1. **No classpath collision**: The runtime uses `io.zenoh.jni.*` exclusively — a namespace already present in both projects and distinct from the public `io.zenoh.*` API. Users see only one `io.zenoh.*` API (from either zenoh-java or zenoh-kotlin).

2. **zenoh-kotlin is truly JNI-free**: No `external fun` declarations, no `System.loadLibrary()`, no Rust compilation, no `.so`/`.dylib` files in zenoh-kotlin. The runtime dependency is "just a Kotlin library" from zenoh-kotlin's perspective.

3. **Minimal logic change in zenoh-kotlin**: The callback assembly code (converting raw JNI bytes to `Sample`, `Query`, etc.) moves from `io.zenoh.jni.JNISession` to `io.zenoh.Session` within zenoh-kotlin. The logic is identical — just in a different class.

4. **zenoh-java changes are contained**: The refactoring of JNI adapters to be primitive-only is internal to zenoh-java; its public `io.zenoh.*` API is unchanged.

5. **Analog in the codebase**: This pattern (extraction of a lower-level binding artifact that both a Java and Kotlin facade share) is exactly the pattern used in large JVM/native projects like RocksDB (jni bindings separate from Java API), Graal SDK (native bindings), etc.

---

## Verification Criteria

1. `zenoh-kotlin` module can be built with NO Rust toolchain installed — must succeed
2. Zero `external fun` declarations in zenoh-kotlin source
3. Zero `System.loadLibrary` calls in zenoh-kotlin source
4. All existing zenoh-kotlin unit tests pass
5. Examples work end-to-end: ZPub, ZSub, ZGet, ZQueryable, ZAdvancedPub, ZAdvancedSub
6. `zenoh-java` unit tests still pass after its internal refactoring
7. A project depending on only `zenoh-kotlin` (not zenoh-java) works correctly at runtime (no FQCN conflicts)

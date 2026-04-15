# Implementation Plan: Create `zenoh-jni-runtime` Module (Kotlin Layer) — Final Revision

## Context and Current State

The Rust JNI exports for advanced pub/sub are **already complete** on the work branch (`zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`):
- `zenoh-jni/src/ext/advanced_publisher.rs` — put, delete, declareMatchingListener, declareBackgroundMatchingListener, getMatchingStatus, freePtrViaJNI
- `zenoh-jni/src/ext/advanced_subscriber.rs` — declareDetectPublishersSubscriber, declareBackgroundDetectPublishersSubscriber, declareSampleMissListener, declareBackgroundSampleMissListener, freePtrViaJNI
- `zenoh-jni/src/ext/matching_listener.rs` — freePtrViaJNI
- `zenoh-jni/src/ext/sample_miss_listener.rs` — freePtrViaJNI
- `zenoh-jni/src/session.rs` — declareAdvancedSubscriberViaJNI, declareAdvancedPublisherViaJNI
- `openSessionViaJNI` now has `@JvmStatic` in Kotlin (`JNISession.kt`), so the Rust symbol has no Companion prefix

The only work remaining is the **Kotlin side**: creating a `zenoh-jni-runtime` Gradle subproject.

---

## Previously Blocking Issues — Now Explicitly Resolved

### Blocker 1: `JNIConfig.ptr` and `JNIKeyExpr.ptr` cross-module visibility

**Problem**: Both classes currently have `internal val ptr: Long`. After moving them to `zenoh-jni-runtime`, `internal` would not be visible to zenoh-java as a separate Gradle module.

**Evidence**:
- `JNISession.kt:52`: `config.jniConfig.ptr` — reads configPtr across module boundary
- `Session.kt` and `KeyExpr.kt`: `keyExpr.jniKeyExpr?.ptr ?: 0` — reads keyExprPtr repeatedly

**Fix**: In the runtime module, both classes must use **`public val ptr: Long`**:
```kotlin
public class JNIConfig(public val ptr: Long)
public class JNIKeyExpr(public val ptr: Long)
```

### Blocker 2: `JNIQuery` internally-consistent calling model

**Problem**: `JNIQuery` has `private val ptr: Long` and external funs that take `queryPtr: Long` as explicit first param. The previous plan said to make external funs `public`, which would require zenoh-java to also read `jniQuery.ptr` — inconsistent.

**Fix**: Follow the **`JNIPublisher` pattern** exactly. Keep `private val ptr: Long`. Add PUBLIC wrapper methods with primitive-only signatures that apply `this.ptr` internally:
```kotlin
class JNIQuery(private val ptr: Long) {
    fun replySuccess(keyExprPtr: Long, keyExprStr: String, payload: ByteArray, encodingId: Int, encodingSchema: String?, timestampEnabled: Boolean, timestampNtp64: Long, attachment: ByteArray?, qosExpress: Boolean) {
        replySuccessViaJNI(this.ptr, keyExprPtr, keyExprStr, payload, encodingId, encodingSchema, timestampEnabled, timestampNtp64, attachment, qosExpress)
    }
    fun replyError(errorPayload: ByteArray, encodingId: Int, encodingSchema: String?) {
        replyErrorViaJNI(this.ptr, errorPayload, encodingId, encodingSchema)
    }
    fun replyDelete(keyExprPtr: Long, keyExprStr: String, timestampEnabled: Boolean, timestampNtp64: Long, attachment: ByteArray?, qosExpress: Boolean) {
        replyDeleteViaJNI(this.ptr, keyExprPtr, keyExprStr, timestampEnabled, timestampNtp64, attachment, qosExpress)
    }
    fun close() { freePtrViaJNI(ptr) }

    private external fun replySuccessViaJNI(queryPtr: Long, keyExprPtr: Long, keyExprString: String, valuePayload: ByteArray, valueEncodingId: Int, valueEncodingSchema: String?, timestampEnabled: Boolean, timestampNtp64: Long, attachment: ByteArray?, qosExpress: Boolean)
    private external fun replyErrorViaJNI(queryPtr: Long, errorValuePayload: ByteArray, errorValueEncoding: Int, encodingSchema: String?)
    private external fun replyDeleteViaJNI(queryPtr: Long, keyExprPtr: Long, keyExprString: String, timestampEnabled: Boolean, timestampNtp64: Long, attachment: ByteArray?, qosExpress: Boolean)
    private external fun freePtrViaJNI(ptr: Long)
}
```
zenoh-java's `Query.kt` calls `jniQuery.replySuccess(primitives...)` — no access to `jniQuery.ptr` needed.

### Blocker 3: `Config` public API preservation

**Problem**: The previous plan's Step 4e sketched `fun default(): Config`, which does not match the current public API. A worker following that sketch would break existing callers.

**Fix**: zenoh-java's `Config.kt` must preserve the **current public API unchanged**. The implementation of each method changes only to wrap the `Long` returned by runtime `JNIConfig`:

| Current public method | Runtime JNIConfig call | Notes |
|---|---|---|
| `loadDefault(): Config` | `Config(JNIConfig(JNIConfig.loadDefaultConfig()))` | Name unchanged |
| `fromFile(file: File): Config` | `Config(JNIConfig(JNIConfig.loadConfigFile(file.toPath().toString())))` | Name unchanged |
| `fromFile(path: Path): Config` | `Config(JNIConfig(JNIConfig.loadConfigFile(path.toString())))` | Name unchanged |
| `fromJson(rawConfig: String): Config` | `Config(JNIConfig(JNIConfig.loadJsonConfig(rawConfig)))` | Name unchanged |
| `fromJson5(rawConfig: String): Config` | `Config(JNIConfig(JNIConfig.loadJsonConfig(rawConfig)))` | Same Rust function handles json5 |
| `fromYaml(rawConfig: String): Config` | `Config(JNIConfig(JNIConfig.loadYamlConfig(rawConfig)))` | Name unchanged |

All public method names, signatures, and Javadoc remain identical.

### Secondary gap: `Session.launch()` → runtime API adaptation

`Session.launch()` calls `JNISession.open(config)` (takes a `Config` object). After the split, runtime's `JNISession.open()` takes `configPtr: Long`. `Session.launch()` must be updated to:
```kotlin
private fun launch(): Session {
    this.jniSession = JNISession.open(config.jniConfig.ptr)
    ...
}
```
This is a one-line change inside zenoh-java.

---

## Critical JNI Binding Pattern (Non-Negotiable Constraint)

All Kotlin JNI adapter classes MUST follow the **`JNIPublisher` pattern** already established in `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNIPublisher.kt`:

1. Instance class with `val ptr: Long` (public in runtime where zenoh-kotlin needs access; can be `private` where ptr not needed cross-module, as in `JNIQuery`)
2. **`private external fun`** declarations — these take the ptr as an **explicit last parameter** (e.g., `private external fun putViaJNI(payload: ByteArray, ..., ptr: Long)`)
3. Public wrapper methods on the instance call the private externals passing `this.ptr`

**Companion-based exports** (JNIConfig, JNIKeyExpr, JNIScout) use a different pattern: the companion object has `private external fun` without `@JvmStatic`, which generates the `_00024Companion_` infix in the symbol name. This must be **preserved** in the runtime module.

---

## Architecture

```
zenoh-kotlin (future, separate repo)
zenoh-java
    ↓ both depend on
zenoh-jni-runtime   ← new Gradle subproject (this PR)
    ├── io.zenoh.ZenohLoad     (PUBLIC, triggers native lib loading)
    ├── io.zenoh.Target        (JVM-only, required by ZenohLoad)
    ├── io.zenoh.jni.*         (JNI adapters, primitive-only, PUBLIC)
    └── io.zenoh.jni.callbacks (callback interfaces, PUBLIC)
    owns zenoh-jni Rust build
```

**Why `ZenohLoad` must be `public`**: Kotlin `internal` is module-scoped. Once `ZenohLoad` lives in `zenoh-jni-runtime` and `zenoh-java` references it (e.g., in `Logger.kt`), a cross-module reference to an `internal` symbol would fail compilation. Both zenoh-java and zenoh-kotlin need to reference `ZenohLoad`.

---

## Step 1: Create `zenoh-jni-runtime` Gradle Subproject

### 1a. `settings.gradle.kts`
Add: `include(":zenoh-jni-runtime")`

### 1b. `zenoh-jni-runtime/build.gradle.kts`
Copy structure from `zenoh-java/build.gradle.kts` with these adaptations:
- Multiplatform Kotlin (JVM + optional Android targets)
- **Owns the `buildZenohJni` Gradle task** pointing to `../zenoh-jni/Cargo.toml`
- Native lib resources:
  - Local (non-remote): `../zenoh-jni/target/{debug|release}` (`*.dylib`, `*.so`, `*.dll`)
  - Remote publication (`isRemotePublication=true`): `../jni-libs` directory (preserve existing CI behavior)
  - Android: `rust-android-gradle` plugin + cargo cross-compilation targets (copy from zenoh-java)
- Published as `org.eclipse.zenoh:zenoh-jni-runtime`
- **Excluded**: kotlin-serialization, dokka, commons-net, guava (those are facade concerns)

### 1c. Move `ZenohLoad` to `zenoh-jni-runtime` (PUBLIC)
- `commonMain/kotlin/io/zenoh/ZenohLoad.kt`: `public expect object ZenohLoad` (was `internal`)
- `jvmMain/kotlin/io/zenoh/ZenohLoad.kt`: Copy the full `actual object ZenohLoad` from `zenoh-java/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` (includes `tryLoadingLocalLibrary()`, `tryLoadingLibraryFromJarPackage()`, `determineTarget()`, etc.)
- `androidMain/kotlin/io/zenoh/ZenohLoad.kt`: Copy `actual object ZenohLoad { System.loadLibrary("zenoh_jni") }` from zenoh-java

### 1d. Move `Target.kt` to `zenoh-jni-runtime`
- `jvmMain/kotlin/io/zenoh/Target.kt`: Copy the full `Target` enum from `zenoh-java/src/jvmMain/kotlin/io/zenoh/Target.kt`
- This is required because the jvmMain `ZenohLoad.kt` depends on it

---

## Step 2: Move/Refactor JNI Adapters into `zenoh-jni-runtime`

**Constraint**: Zero imports of `io.zenoh.*` facade types. Only primitives, `ByteArray`, `Long`, `String`, `Boolean`, `Int`, and callback interfaces.

All moved classes must have **`public`** visibility (previously `internal`) so zenoh-kotlin can access them.

### 2a. Classes moved with visibility change only (`internal` → `public`):
These are already primitive-only; just change visibility and remove ZenohLoad imports (it's now in the same module but publicly accessible from companion init blocks).

- `JNISubscriber.kt` — `class JNISubscriber(val ptr: Long)` with `fun close()` and `private external fun freePtrViaJNI(ptr: Long)`
- `JNIQueryable.kt` — same pattern
- `JNILivelinessToken.kt` — keep `companion object` with `external fun undeclareViaJNI(ptr: Long)` (companion pattern → preserves JNI symbol shape)
- `JNIZenohId.kt` — check current content; if already primitive, move as-is
- `callbacks/JNISubscriberCallback.kt`, `JNIQueryableCallback.kt`, `JNIGetCallback.kt`, `JNIScoutCallback.kt`, `JNIOnCloseCallback.kt` — move as-is, change to `public`

### 2b. Classes requiring refactoring (remove facade-type references):

**`JNISession.kt`**:
- Keep instance class `class JNISession(val sessionPtr: Long)` (public val)
- Keep companion object with `fun open(configPtr: Long): JNISession` (takes Long, not Config — see Secondary gap above)
- Keep `@JvmStatic` on `openSessionViaJNI` in companion (matches unified Rust symbol without Companion prefix)
- Make all existing `private external fun` declarations **`public external fun`** so zenoh-kotlin can call them directly
- Add new public external fun declarations matching the Rust session.rs exports:
  ```kotlin
  @Throws(ZError::class)
  external fun declareAdvancedSubscriberViaJNI(
      keyExprPtr: Long, keyExprStr: String, sessionPtr: Long,
      historyConfigEnabled: Boolean, historyDetectLatePublishers: Boolean,
      historyMaxSamples: Long, historyMaxAgeSeconds: Double,
      recoveryConfigEnabled: Boolean, recoveryConfigIsHeartbeat: Boolean, recoveryQueryPeriodMs: Long,
      subscriberDetection: Boolean,
      callback: JNISubscriberCallback, onClose: JNIOnCloseCallback,
  ): Long

  @Throws(ZError::class)
  external fun declareAdvancedPublisherViaJNI(
      keyExprPtr: Long, keyExprStr: String, sessionPtr: Long,
      congestionControl: Int, priority: Int, isExpress: Boolean, reliability: Int,
      cacheEnabled: Boolean, cacheMaxSamples: Long,
      cacheRepliesPriority: Int, cacheRepliesCongestionControl: Int, cacheRepliesIsExpress: Boolean,
      sampleMissDetectionEnabled: Boolean, sampleMissDetectionEnableHeartbeat: Boolean,
      sampleMissDetectionHeartbeatMs: Long, sampleMissDetectionHeartbeatIsSporadic: Boolean,
      publisherDetection: Boolean,
  ): Long
  ```
- Remove all high-level facade wrapper methods (`declarePublisher(keyExpr: KeyExpr, ...)`, `declareSubscriberWithHandler(...)`, etc.) — these move to zenoh-java's `Session.kt`

**`JNIPublisher.kt`**:
- Change `private val ptr` → **`public val ptr`** (zenoh-kotlin needs direct access)
- Remove facade-typed wrapper methods; add public wrapper methods taking primitives: `put(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?)` and `delete(attachment: ByteArray?)`
- These public methods call the existing `private external fun putViaJNI(...)` and `deleteViaJNI(...)`
- Remove `import io.zenoh.bytes.Encoding` and `import io.zenoh.bytes.IntoZBytes`

**`JNIConfig.kt`** — *(Blocker 1 explicitly resolved here)*:
- Change to `public class JNIConfig(public val ptr: Long)` — required for zenoh-java cross-module access
- Companion factory methods return `Long` (not `Config`):
  ```kotlin
  fun loadDefaultConfig(): Long { return loadDefaultConfigViaJNI() }
  fun loadConfigFile(path: String): Long { return loadConfigFileViaJNI(path) }
  fun loadJsonConfig(rawConfig: String): Long { return loadJsonConfigViaJNI(rawConfig) }
  fun loadYamlConfig(rawConfig: String): Long { return loadYamlConfigViaJNI(rawConfig) }
  ```
- Remove `import io.zenoh.Config`; `Config` wrapping moves to zenoh-java's `Config.kt`
- **Preserve companion-based structure** — do NOT add `@JvmStatic` to external funs. Rust exports use `Java_io_zenoh_jni_JNIConfig_00024Companion_loadDefaultConfigViaJNI` (with Companion prefix), so companion-without-JvmStatic is mandatory.
- `getJson`, `insertJson5`, `close` — unchanged (already primitive)

**`JNIKeyExpr.kt`** — *(Blocker 1 explicitly resolved here)*:
- Change to `public class JNIKeyExpr(public val ptr: Long)` — required for zenoh-java cross-module access  
- Companion factory methods return `String` (not `KeyExpr`):
  ```kotlin
  fun tryFrom(keyExpr: String): String { return tryFromViaJNI(keyExpr) }
  fun autocanonize(keyExpr: String): String { return autocanonizeViaJNI(keyExpr) }
  ```
- Comparison methods already take primitives `(ptrA: Long, strA: String, ptrB: Long, strB: String)` — unchanged in signature
- `join` and `concat` wrapper methods return `String` instead of `KeyExpr`
- Remove `import io.zenoh.keyexpr.KeyExpr`, `import io.zenoh.keyexpr.SetIntersectionLevel`
- **Preserve companion-based structure** — same reasoning as JNIConfig: Rust exports use `_00024Companion_` prefix

**`JNIQuery.kt`** — *(Blocker 2 explicitly resolved here)*:
- Keep `private val ptr: Long` — do NOT expose ptr
- Remove façade-typed wrapper methods: `replySuccess(sample: Sample)`, `replyError(error: IntoZBytes, encoding: Encoding)`, `replyDelete(keyExpr: KeyExpr, ...)`
- Add PUBLIC wrapper methods with primitive-only signatures that apply `this.ptr` internally (see Blocker 2 section above for exact signatures)
- Keep the `private external fun replySuccessViaJNI(queryPtr: Long, ...)` etc. unchanged — they already take all primitives
- zenoh-java's `Query.kt` calls the public wrappers (e.g., `jniQuery.replySuccess(keyExprPtr, keyExprStr, payload, ...)`) after decomposing facade types; it never needs `jniQuery.ptr`
- Remove all facade imports (`Sample`, `KeyExpr`, `Encoding`, `IntoZBytes`, `QoS`)

**`JNIQuerier.kt`**:
- Remove `performGetWithCallback(keyExpr: KeyExpr, ...)`, `performGetWithHandler(...)`, and the private `performGet(...)` helper methods
- Make `getViaJNI(querierPtr, keyExprPtr, keyExprString, parameters, callback, onClose, attachmentBytes, payload, encodingId, encodingSchema)` a **public wrapper method** that applies `this.ptr` (matching JNIPublisher pattern) OR as a public external fun — keep `querierPtr` as explicit first param if it's an instance-level external
- Remove all facade imports (`KeyExpr`, `Encoding`, `IntoZBytes`, `Reply`, `Sample`, `QoS`, etc.)
- zenoh-java's `Querier.kt` assembles the `JNIGetCallback` and Reply construction

**`JNIScout.kt`** (CRITICAL — preserve Companion prefix):
- Keep the `companion object` structure
- Keep `private external fun scoutViaJNI(...)` WITHOUT `@JvmStatic` — this preserves the Rust symbol `Java_io_zenoh_jni_JNIScout_00024Companion_scoutViaJNI`
- Remove `scoutWithHandler(...)` and `scoutWithCallback(...)` facade wrappers
- Add a public companion method `scout(whatAmI: Int, callback: JNIScoutCallback, onClose: JNIOnCloseCallback, configPtr: Long): Long` that calls `scoutViaJNI` directly
- `freePtrViaJNI(ptr: Long)` stays as `external fun` in companion (already public)
- Remove all facade imports (`Config`, `Hello`, `WhatAmI`, `ZenohId`, `HandlerScout`, `CallbackScout`)

**`JNILiveliness.kt`**:
- Keep as `object JNILiveliness` (no ptr needed for object-level dispatching)
- Refactor `get(...)` → `get(sessionPtr: Long, keyExprPtr: Long, keyExprStr: String, callback: JNIGetCallback, timeoutMs: Long, onClose: JNIOnCloseCallback)` — no Reply construction
- Refactor `declareToken(...)` → return `Long` directly
- Refactor `declareSubscriber(...)` → `declareSubscriber(sessionPtr: Long, keyExprPtr: Long, keyExprStr: String, callback: JNISubscriberCallback, history: Boolean, onClose: JNIOnCloseCallback): Long`
- Remove all facade imports and facade construction

### 2c. Classes that stay in `zenoh-java` (NOT moved to runtime):
- **`JNIZBytes.kt`**: Methods return/take `ZBytes` facade — violates primitive-only constraint. zenoh-kotlin has its own serialization.
- **`Logger.kt`**: `startLogsViaJNI` is bound to `io.zenoh.Logger` class (Rust symbol `Java_io_zenoh_Logger_00024Companion_startLogsViaJNI`). Not a JNI adapter — stays in zenoh-java.

---

## Step 3: New Files in Runtime (Advanced Pub/Sub Adapters)

All follow the `JNIPublisher` pattern.

### `JNIAdvancedPublisher.kt`
```kotlin
class JNIAdvancedPublisher(val ptr: Long) {
    fun put(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?) {
        putViaJNI(payload, encodingId, encodingSchema, attachment, ptr)
    }
    fun delete(attachment: ByteArray?) { deleteViaJNI(attachment, ptr) }
    fun declareMatchingListener(callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback): Long {
        return declareMatchingListenerViaJNI(ptr, callback, onClose)
    }
    fun declareBackgroundMatchingListener(callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback) {
        declareBackgroundMatchingListenerViaJNI(ptr, callback, onClose)
    }
    fun getMatchingStatus(): Boolean { return getMatchingStatusViaJNI(ptr) }
    fun close() { freePtrViaJNI(ptr) }

    private external fun putViaJNI(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?, ptr: Long)
    private external fun deleteViaJNI(attachment: ByteArray?, ptr: Long)
    private external fun declareMatchingListenerViaJNI(ptr: Long, callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback): Long
    private external fun declareBackgroundMatchingListenerViaJNI(ptr: Long, callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback)
    private external fun getMatchingStatusViaJNI(ptr: Long): Boolean
    private external fun freePtrViaJNI(ptr: Long)
}
```

### `JNIAdvancedSubscriber.kt`
```kotlin
class JNIAdvancedSubscriber(val ptr: Long) {
    fun declareDetectPublishersSubscriber(history: Boolean, callback: JNISubscriberCallback, onClose: JNIOnCloseCallback): Long {
        return declareDetectPublishersSubscriberViaJNI(ptr, history, callback, onClose)
    }
    fun declareBackgroundDetectPublishersSubscriber(history: Boolean, callback: JNISubscriberCallback, onClose: JNIOnCloseCallback) {
        declareBackgroundDetectPublishersSubscriberViaJNI(ptr, history, callback, onClose)
    }
    fun declareSampleMissListener(callback: JNISampleMissListenerCallback, onClose: JNIOnCloseCallback): Long {
        return declareSampleMissListenerViaJNI(ptr, callback, onClose)
    }
    fun declareBackgroundSampleMissListener(callback: JNISampleMissListenerCallback, onClose: JNIOnCloseCallback) {
        declareBackgroundSampleMissListenerViaJNI(ptr, callback, onClose)
    }
    fun close() { freePtrViaJNI(ptr) }

    private external fun declareDetectPublishersSubscriberViaJNI(ptr: Long, history: Boolean, callback: JNISubscriberCallback, onClose: JNIOnCloseCallback): Long
    private external fun declareBackgroundDetectPublishersSubscriberViaJNI(ptr: Long, history: Boolean, callback: JNISubscriberCallback, onClose: JNIOnCloseCallback)
    private external fun declareSampleMissListenerViaJNI(ptr: Long, callback: JNISampleMissListenerCallback, onClose: JNIOnCloseCallback): Long
    private external fun declareBackgroundSampleMissListenerViaJNI(ptr: Long, callback: JNISampleMissListenerCallback, onClose: JNIOnCloseCallback)
    private external fun freePtrViaJNI(ptr: Long)
}
```

### `JNIMatchingListener.kt`
```kotlin
class JNIMatchingListener(val ptr: Long) {
    fun close() { freePtrViaJNI(ptr) }
    private external fun freePtrViaJNI(ptr: Long)
}
```

### `JNISampleMissListener.kt`
```kotlin
class JNISampleMissListener(val ptr: Long) {
    fun close() { freePtrViaJNI(ptr) }
    private external fun freePtrViaJNI(ptr: Long)
}
```

### `callbacks/JNIMatchingListenerCallback.kt`
```kotlin
fun interface JNIMatchingListenerCallback {
    fun run(matching: Boolean)
}
```

### `callbacks/JNISampleMissListenerCallback.kt`
```kotlin
fun interface JNISampleMissListenerCallback {
    fun run(zidLower: Long, zidUpper: Long, eid: Long, nb: Long)
}
```

---

## Step 4: Refactor `zenoh-java` to Use Runtime

### 4a. `zenoh-java/build.gradle.kts`:
- Remove `buildZenohJni` Gradle task and `buildZenohJNI` function (moved to runtime)
- Remove native lib resources from `jvmMain`/`jvmTest` source sets (packaged by runtime's JAR)
- Add: `implementation(project(":zenoh-jni-runtime"))`
- Keep all other dependencies (commons-net, guava, kotlin-serialization)
- Keep `jvmArgs("-Djava.library.path=../zenoh-jni/target/$buildMode")` for tests

### 4b. Remove `ZenohLoad` expect/actual from `zenoh-java`:
- Delete `internal expect object ZenohLoad` from `commonMain/kotlin/io/zenoh/Zenoh.kt`
- Delete `internal actual object ZenohLoad` from `jvmMain/kotlin/io/zenoh/Zenoh.kt`
- Delete `internal actual object ZenohLoad` from `androidMain/kotlin/io.zenoh/Zenoh.kt`
- Also remove `Target.kt` from `zenoh-java` (moved to runtime)

### 4c. `zenoh-java/src/commonMain/kotlin/io/zenoh/Logger.kt`:
Add explicit `ZenohLoad` reference before JNI call to prevent `UnsatisfiedLinkError`:
```kotlin
fun start(filter: String) {
    ZenohLoad  // Ensures native library is loaded (ZenohLoad is now in zenoh-jni-runtime)
    startLogsViaJNI(filter)
}
```

### 4d. Delete from `zenoh-java/src/`:
All `io.zenoh.jni.*` files **except `JNIZBytes.kt`**:
- `JNISession.kt`, `JNIPublisher.kt`, `JNIConfig.kt`, `JNIKeyExpr.kt`
- `JNIQuery.kt`, `JNIQuerier.kt`, `JNIScout.kt`, `JNILiveliness.kt`
- `JNISubscriber.kt`, `JNIQueryable.kt`, `JNILivelinessToken.kt`, `JNIZenohId.kt`
- `callbacks/JNISubscriberCallback.kt`, `JNIQueryableCallback.kt`, `JNIGetCallback.kt`, `JNIScoutCallback.kt`, `JNIOnCloseCallback.kt`

### 4e. Update zenoh-java facade classes:

**`Session.kt`**:
- Update `Session.launch()` to call `JNISession.open(config.jniConfig.ptr)` (not `JNISession.open(config)`) — adapts to runtime's `Long`-taking API
- Inline callback assembly previously in `JNISession.kt`:
  - `declarePublisher(keyExpr, options)` → calls `jniSession.declarePublisherViaJNI(keyExpr.jniKeyExpr?.ptr ?: 0, keyExpr.keyExpr, sessionPtr, ...)`, wraps result `Long` in `Publisher(keyExpr, ..., JNIPublisher(ptr))`
  - `declareSubscriberWithHandler/WithCallback(...)` → creates `JNISubscriberCallback { ke, payload, ... -> Sample(...) }` inline, calls `jniSession.declareSubscriberViaJNI(...)`, wraps in `HandlerSubscriber`/`CallbackSubscriber`
  - `declareQueryableWith*(...)` → creates `JNIQueryableCallback { ... -> Query(...) }` inline, calls `jniSession.declareQueryableViaJNI(...)`, wraps
  - `declareQuerier(...)` → calls `jniSession.declareQuerierViaJNI(...)`, wraps in `Querier`
  - `performGet*(...)` → creates `JNIGetCallback { ... -> Reply.Success/Error(...) }` inline, calls `jniSession.getViaJNI(...)`
  - `zid/peersZid/routersZid` → calls JNI methods, wraps `ByteArray` → `ZenohId`
  - `declareKeyExpr/undeclareKeyExpr` → calls JNI methods, wraps `Long` → `KeyExpr`
  - `performPut/performDelete` → calls `jniSession.putViaJNI(...)`/`jniSession.deleteViaJNI(...)` with primitives

**`Config.kt`** — *(Blocker 3 explicitly resolved here)*:
Preserve the exact current public API. Only the internal implementation changes to wrap `Long`:
```kotlin
// ALL existing public method names preserved exactly:
@JvmStatic
fun loadDefault(): Config = Config(JNIConfig(JNIConfig.loadDefaultConfig()))

@JvmStatic
@Throws(ZError::class)
fun fromFile(file: File): Config = Config(JNIConfig(JNIConfig.loadConfigFile(file.toPath().toString())))

@JvmStatic
@Throws(ZError::class)
fun fromFile(path: Path): Config = Config(JNIConfig(JNIConfig.loadConfigFile(path.toString())))

@JvmStatic
@Throws(ZError::class)
fun fromJson(rawConfig: String): Config = Config(JNIConfig(JNIConfig.loadJsonConfig(rawConfig)))

@JvmStatic
@Throws(ZError::class)
fun fromJson5(rawConfig: String): Config = Config(JNIConfig(JNIConfig.loadJsonConfig(rawConfig)))
// ^ fromJson5 intentionally maps to loadJsonConfig (same Rust function handles json5)

@JvmStatic
@Throws(ZError::class)
fun fromYaml(rawConfig: String): Config = Config(JNIConfig(JNIConfig.loadYamlConfig(rawConfig)))
```
`Config` class itself changes to: `class Config internal constructor(internal val jniConfig: JNIConfig)` with `jniConfig` remaining accessible for `.ptr` reads in `JNISession` etc.

**`KeyExpr.kt`**: Update to use String from runtime:
- `JNIKeyExpr.tryFrom(keyExpr)` now returns `String` → wrap: `KeyExpr(JNIKeyExpr.tryFrom(keyExpr), null)`
- Comparison methods: pass `(keyExprA.jniKeyExpr?.ptr ?: 0, keyExprA.keyExpr, keyExprB.jniKeyExpr?.ptr ?: 0, keyExprB.keyExpr)` to runtime methods
- `JNIKeyExpr.intersects(a, b)` still works but now `JNIKeyExpr` is in the runtime module

**`Publisher.kt`**: `put(IntoZBytes, Encoding?, IntoZBytes?)` decomposes to primitives and calls `jniPublisher.put(payload.into().bytes, encoding.id, encoding.schema, attachment?.into()?.bytes)`

**`Query.kt`** — *(Blocker 2 reflected here)*:
`replySuccess(sample: Sample)` decomposes sample → primitives and calls `jniQuery.replySuccess(keyExprPtr, keyExprStr, payload, encodingId, encodingSchema, timestampEnabled, timestampNtp64, attachment, qosExpress)`. No access to `jniQuery.ptr` needed since runtime wraps it internally.

**`Zenoh.kt`** (scouting): Scout methods build inline `JNIScoutCallback { ... -> callback.run(Hello(...)) }`, call `JNIScout.scout(binaryWhatAmI, scoutCallback, onClose, configPtr)`, wrap returned `Long` in `CallbackScout`/`HandlerScout`

**`Liveliness.kt`**: Pass keyExpr as `(sessionPtr, keyExprPtr, keyExprStr)` primitives to runtime `JNILiveliness`; wrap returned `Long` in `LivelinessToken(JNILivelinessToken(ptr))`, etc.

**`Querier.kt`**: `performGet(keyExpr, ...)` creates `JNIGetCallback { ... -> Reply(...) }` inline, calls `jniQuerier.getViaJNI(ptr, keyExprPtr, keyExprStr, params, callback, onClose, attachmentBytes, payloadBytes, encodingId, encodingSchema)`

---

## Adversarial Issues Resolution

| Issue | Resolution |
|-------|------------|
| `ZenohLoad` `internal` across modules | `ZenohLoad` is `public` in zenoh-jni-runtime |
| `Target.kt` missing from plan | Explicitly moved to `zenoh-jni-runtime/src/jvmMain/` |
| `JNIConfig.ptr` cross-module visibility | **NEW**: `public class JNIConfig(public val ptr: Long)` |
| `JNIKeyExpr.ptr` cross-module visibility | **NEW**: `public class JNIKeyExpr(public val ptr: Long)` |
| `JNIQuery` calling model inconsistency | **NEW**: Keep `private val ptr`, add public primitive wrapper methods that apply `this.ptr`; no ptr exposure needed |
| `Config` public API preservation (loadDefault, fromJson5) | **NEW**: All public method names unchanged; `fromJson5` maps to `loadJsonConfig`; no `default()` rename |
| `Session.launch()` → runtime API adaptation | **NEW**: `Session.launch()` calls `JNISession.open(config.jniConfig.ptr)` |
| `JNIConfig`/`JNIKeyExpr` companion binding preservation | Companion WITHOUT `@JvmStatic` explicitly specified — preserves `_00024Companion_` JNI symbol |
| Advanced adapter JNI pattern mismatch | All follow `JNIPublisher` pattern: `private external fun` with explicit `ptr: Long` last param |
| `detect-publishers history` param missing | `declareDetectPublishersSubscriber(history: Boolean, ...)` explicitly includes it |
| `JNIZBytes`/`Logger` facade dependency | `JNIZBytes` stays in zenoh-java; `Logger.kt` adds `ZenohLoad` reference before external call |
| Scouting `_00024Companion_` preserved | `JNIScout` companion WITHOUT `@JvmStatic` on `scoutViaJNI` |
| Build: local + remote + Android | `zenoh-jni-runtime/build.gradle.kts` copies all three packaging patterns from zenoh-java |

---

## File Summary

| File | Action |
|------|--------|
| `settings.gradle.kts` | Add `include(":zenoh-jni-runtime")` |
| `zenoh-jni-runtime/build.gradle.kts` | New — native packaging, no serialization/dokka/guava |
| `zenoh-jni-runtime/src/commonMain/.../ZenohLoad.kt` | New — `public expect object ZenohLoad` |
| `zenoh-jni-runtime/src/jvmMain/.../ZenohLoad.kt` | New — moved from zenoh-java's jvmMain |
| `zenoh-jni-runtime/src/jvmMain/.../Target.kt` | New — moved from zenoh-java's jvmMain |
| `zenoh-jni-runtime/src/androidMain/.../ZenohLoad.kt` | New — moved from zenoh-java's androidMain |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNISession.kt` | New — public externals + new advanced methods |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIPublisher.kt` | New — `public val ptr`, primitive put/delete |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIConfig.kt` | New — `public val ptr`, factory methods return Long |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIKeyExpr.kt` | New — `public val ptr`, factory methods return String |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIQuery.kt` | New — `private val ptr`, public primitive wrappers |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIQuerier.kt` | New — public getViaJNI, no facade wrappers |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIScout.kt` | New — companion WITHOUT @JvmStatic on scoutViaJNI |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNILiveliness.kt` | New — primitive API, returns Long |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNISubscriber.kt` | New — moved as-is, public |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIQueryable.kt` | New — moved as-is, public |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNILivelinessToken.kt` | New — moved as-is, public |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIZenohId.kt` | New — moved as-is, public |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIAdvancedPublisher.kt` | New — JNIPublisher pattern |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIAdvancedSubscriber.kt` | New — JNIPublisher pattern, history bool |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIMatchingListener.kt` | New |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNISampleMissListener.kt` | New |
| `zenoh-jni-runtime/src/commonMain/.../jni/callbacks/` (all 5 existing) | New — moved as-is, public |
| `zenoh-jni-runtime/src/commonMain/.../jni/callbacks/JNIMatchingListenerCallback.kt` | New — `fun run(Boolean)` |
| `zenoh-jni-runtime/src/commonMain/.../jni/callbacks/JNISampleMissListenerCallback.kt` | New — `fun run(Long, Long, Long, Long)` |
| `zenoh-java/build.gradle.kts` | Remove Rust build task, add runtime dep |
| `zenoh-java/src/jvmMain/.../Zenoh.kt` | Remove ZenohLoad actual + Target.kt |
| `zenoh-java/src/androidMain/.../Zenoh.kt` | Remove ZenohLoad actual |
| `zenoh-java/src/commonMain/.../Zenoh.kt` | Remove ZenohLoad expect |
| `zenoh-java/src/commonMain/.../Logger.kt` | Add ZenohLoad reference before startLogsViaJNI |
| `zenoh-java/src/commonMain/.../Session.kt` | Update launch() + inline callback assembly + facade wrapping |
| `zenoh-java/src/commonMain/.../Config.kt` | Preserve exact public API, wrap Long → Config |
| `zenoh-java/src/commonMain/.../keyexpr/KeyExpr.kt` | Wrap String primitives |
| `zenoh-java/src/commonMain/.../pubsub/Publisher.kt` | Decompose IntoZBytes/Encoding → bytes |
| `zenoh-java/src/commonMain/.../query/Query.kt` | Decompose Sample → primitives, call public wrappers |
| `zenoh-java/src/commonMain/.../Zenoh.kt` | Inline JNIScoutCallback assembly |
| `zenoh-java/src/commonMain/.../liveliness/Liveliness.kt` | Use primitive JNILiveliness API |
| `zenoh-java/src/commonMain/.../query/Querier.kt` | Inline JNIGetCallback, call runtime getViaJNI |
| `zenoh-java/src/commonMain/.../jni/` (all except JNIZBytes.kt) | Delete — moved to runtime |

---

## Verification

1. `./gradlew :zenoh-jni-runtime:build` — runtime compiles without any `io.zenoh.*` facade imports
2. `./gradlew :zenoh-java:test` — all existing tests pass
3. `grep -r "^import io\.zenoh\." zenoh-jni-runtime/src/` — zero results (only `io.zenoh.jni.*` and `io.zenoh.ZenohLoad`/`io.zenoh.Target` allowed)
4. `grep -rn "ZenohLoad\|System.load" zenoh-java/src/commonMain/` — only `Logger.kt` reference
5. Run ZPub/ZSub/ZGet/ZQueryable examples end-to-end
6. Verify `JNIAdvancedPublisher`/`JNIAdvancedSubscriber` parameter counts match Rust exports exactly

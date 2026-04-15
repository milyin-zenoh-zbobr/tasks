# Implementation Plan: Create `zenoh-jni-runtime` Module (Kotlin Layer)

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

## Critical JNI Binding Pattern (Non-Negotiable Constraint)

All Kotlin JNI adapter classes MUST follow the **`JNIPublisher` pattern** already established in `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNIPublisher.kt`:

1. Instance class with `val ptr: Long` (or `private val ptr: Long` for existing ones, `val ptr: Long` for runtime where zenoh-kotlin needs access)
2. **`private external fun`** declarations — these take the ptr as an **explicit last parameter** (e.g., `private external fun putViaJNI(payload: ByteArray, ..., ptr: Long)`)
3. Public wrapper methods on the instance call the private externals passing `this.ptr`

This is mandatory because the Rust functions are static-style JNI exports (take `JClass`), not true instance methods. If the external fun is declared inside a class without an explicit ptr parameter, Kotlin generates the same JNI symbol but the Rust function won't find the pointer — causing `UnsatisfiedLinkError`.

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
- Keep companion object with `fun open(configPtr: Long): JNISession` (takes Long, not Config)
- Keep `@JvmStatic` on `openSessionViaJNI` in companion (matches unified Rust symbol without Companion prefix)
- Make all existing `private external fun` declarations **`public external fun`** so zenoh-kotlin can call them directly
- Add new public external fun declarations matching the Rust session.rs exports:
  ```kotlin
  @Throws(ZError::class)
  external fun declareAdvancedSubscriberViaJNI(
      keyExprPtr: Long,
      keyExprStr: String,
      sessionPtr: Long,
      historyConfigEnabled: Boolean,
      historyDetectLatePublishers: Boolean,
      historyMaxSamples: Long,
      historyMaxAgeSeconds: Double,
      recoveryConfigEnabled: Boolean,
      recoveryConfigIsHeartbeat: Boolean,
      recoveryQueryPeriodMs: Long,
      subscriberDetection: Boolean,
      callback: JNISubscriberCallback,
      onClose: JNIOnCloseCallback,
  ): Long

  @Throws(ZError::class)
  external fun declareAdvancedPublisherViaJNI(
      keyExprPtr: Long,
      keyExprStr: String,
      sessionPtr: Long,
      congestionControl: Int,
      priority: Int,
      isExpress: Boolean,
      reliability: Int,
      cacheEnabled: Boolean,
      cacheMaxSamples: Long,
      cacheRepliesPriority: Int,
      cacheRepliesCongestionControl: Int,
      cacheRepliesIsExpress: Boolean,
      sampleMissDetectionEnabled: Boolean,
      sampleMissDetectionEnableHeartbeat: Boolean,
      sampleMissDetectionHeartbeatMs: Long,
      sampleMissDetectionHeartbeatIsSporadic: Boolean,
      publisherDetection: Boolean,
  ): Long
  ```
- Remove all high-level facade wrapper methods (`declarePublisher(keyExpr: KeyExpr, ...)`, `declareSubscriberWithHandler(...)`, etc.) — these move to zenoh-java's `Session.kt`

**`JNIPublisher.kt`**:
- Change `private val ptr` → `public val ptr` (zenoh-kotlin needs direct access)
- Remove facade-typed wrapper methods: `put(payload: IntoZBytes, encoding: Encoding?, attachment: IntoZBytes?)` and `delete(attachment: IntoZBytes?)`
- Add public wrapper methods taking primitives: `put(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?)` and `delete(attachment: ByteArray?)`
- These public methods call the existing `private external fun putViaJNI(...)` and `deleteViaJNI(...)`
- Remove `import io.zenoh.bytes.Encoding` and `import io.zenoh.bytes.IntoZBytes`

**`JNIConfig.kt`**:
- Factory methods return `Long` instead of `Config`:
  ```kotlin
  fun loadDefaultConfig(): Long { return loadDefaultConfigViaJNI() }
  fun loadConfigFile(path: String): Long { return loadConfigFileViaJNI(path) }
  fun loadJsonConfig(rawConfig: String): Long { return loadJsonConfigViaJNI(rawConfig) }
  fun loadYamlConfig(rawConfig: String): Long { return loadYamlConfigViaJNI(rawConfig) }
  ```
- Remove `import io.zenoh.Config`; `Config` wrapping moves to zenoh-java's `Config.kt`
- **Preserve companion-based structure** — do NOT add `@JvmStatic` to external funs. Rust exports use `Java_io_zenoh_jni_JNIConfig_00024Companion_loadDefaultConfigViaJNI` (with Companion prefix), so companion-without-JvmStatic is mandatory.
- `getJson`, `insertJson5`, `close` — unchanged (already primitive)

**`JNIKeyExpr.kt`**:
- Factory methods already return `String` at the external level; remove the `KeyExpr(...)` wrapping:
  ```kotlin
  fun tryFrom(keyExpr: String): String { return tryFromViaJNI(keyExpr) }
  fun autocanonize(keyExpr: String): String { return autocanonizeViaJNI(keyExpr) }
  ```
- Comparison methods already take `(ptrA: Long, strA: String, ptrB: Long, strB: String)` — unchanged
- `joinViaJNI` and `concatViaJNI` already return `String` — just rename wrappers to return String instead of KeyExpr
- Remove `import io.zenoh.keyexpr.KeyExpr`, `import io.zenoh.keyexpr.SetIntersectionLevel`
- **Preserve companion-based structure** — same reasoning as JNIConfig: Rust exports use `_00024Companion_` prefix

**`JNIQuery.kt`**:
- Remove facade-typed wrapper methods: `replySuccess(sample: Sample)`, `replyError(error: IntoZBytes, encoding: Encoding)`, `replyDelete(keyExpr: KeyExpr, ...)`
- Make external funs **directly public** (`public external fun replySuccessViaJNI(...)`, etc.) — already take primitives so no refactoring needed
- Remove all facade imports (`Sample`, `KeyExpr`, `Encoding`, `IntoZBytes`, `QoS`)
- zenoh-java's `Query.kt` will call `jniQuery.replySuccessViaJNI(...)` directly, decomposing Sample → primitives

**`JNIQuerier.kt`**:
- Remove `performGetWithCallback(keyExpr: KeyExpr, ...)`, `performGetWithHandler(...)`, and the private `performGet(...)` helper methods
- Make `getViaJNI(querierPtr, keyExprPtr, keyExprString, parameters, callback, onClose, attachmentBytes, payload, encodingId, encodingSchema)` **directly public**
- Remove all facade imports (`KeyExpr`, `Encoding`, `IntoZBytes`, `Reply`, `Sample`, `QoS`, etc.)
- zenoh-java's `Querier.kt` assembles the `JNIGetCallback` and Reply construction

**`JNIScout.kt`** (CRITICAL — preserve Companion prefix):
- Keep the `companion object` structure
- Keep `private external fun scoutViaJNI(...)` WITHOUT `@JvmStatic` — this preserves the Rust symbol `Java_io_zenoh_jni_JNIScout_00024Companion_scoutViaJNI`
- Remove `scoutWithHandler(...)` and `scoutWithCallback(...)` facade wrappers (they create `Hello`, `HandlerScout`, `CallbackScout` — all facade types)
- Add a public companion method `scout(whatAmI: Int, callback: JNIScoutCallback, onClose: JNIOnCloseCallback, configPtr: Long): Long` that calls `scoutViaJNI` directly
- `freePtrViaJNI(ptr: Long)` stays as `external fun` in companion (already public)
- Remove all facade imports (`Config`, `Hello`, `WhatAmI`, `ZenohId`, `HandlerScout`, `CallbackScout`)
- zenoh-java's `Zenoh.kt` builds the `JNIScoutCallback` inline (constructing `Hello` objects)

**`JNILiveliness.kt`**:
- Keep as `object JNILiveliness` (no ptr needed for object-level dispatching)
- Refactor `get(jniSession, keyExpr: KeyExpr, ...)` → `get(sessionPtr: Long, keyExprPtr: Long, keyExprStr: String, callback: JNIGetCallback, timeoutMs: Long, onClose: JNIOnCloseCallback)` — no Reply construction
- Refactor `declareToken(jniSession, keyExpr: KeyExpr)` → return `Long` directly (was returning `LivelinessToken`)
- Refactor `declareSubscriber(jniSession, keyExpr: KeyExpr, ...)` → `declareSubscriber(sessionPtr: Long, keyExprPtr: Long, keyExprStr: String, callback: JNISubscriberCallback, history: Boolean, onClose: JNIOnCloseCallback): Long`
- Remove all facade imports and facade construction
- zenoh-java's `Liveliness.kt` does the facade wrapping

### 2c. Classes that stay in `zenoh-java` (NOT moved to runtime):
- **`JNIZBytes.kt`**: External fun `deserialize(ZBytes)` / `serialize` methods return `ZBytes` facade — violates primitive-only constraint. zenoh-kotlin has its own serialization and doesn't need it.
- **`Logger.kt`**: `startLogsViaJNI` is a companion external bound to `io.zenoh.Logger` class in zenoh-java (Rust symbol `Java_io_zenoh_Logger_00024Companion_startLogsViaJNI`). Not a JNI adapter — stays in zenoh-java.

---

## Step 3: New Files in Runtime (Advanced Pub/Sub Adapters)

All follow the `JNIPublisher` pattern: instance class with `val ptr: Long`, `private external fun` with ptr as explicit parameter.

### `JNIAdvancedPublisher.kt`
```kotlin
class JNIAdvancedPublisher(val ptr: Long) {
    fun put(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?) {
        putViaJNI(payload, encodingId, encodingSchema, attachment, ptr)
    }
    fun delete(attachment: ByteArray?) {
        deleteViaJNI(attachment, ptr)
    }
    fun declareMatchingListener(callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback): Long {
        return declareMatchingListenerViaJNI(ptr, callback, onClose)
    }
    fun declareBackgroundMatchingListener(callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback) {
        declareBackgroundMatchingListenerViaJNI(ptr, callback, onClose)
    }
    fun getMatchingStatus(): Boolean {
        return getMatchingStatusViaJNI(ptr)
    }
    fun close() { freePtrViaJNI(ptr) }

    // Rust: Java_io_zenoh_jni_JNIAdvancedPublisher_putViaJNI(env, class, payload, encodingId, encodingSchema, attachment, publisher_ptr)
    private external fun putViaJNI(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?, ptr: Long)
    // Rust: Java_io_zenoh_jni_JNIAdvancedPublisher_deleteViaJNI(env, class, attachment, publisher_ptr)
    private external fun deleteViaJNI(attachment: ByteArray?, ptr: Long)
    // Rust: Java_io_zenoh_jni_JNIAdvancedPublisher_declareMatchingListenerViaJNI(env, class, advanced_publisher_ptr, callback, on_close) -> ptr
    private external fun declareMatchingListenerViaJNI(ptr: Long, callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback): Long
    // Rust: Java_io_zenoh_jni_JNIAdvancedPublisher_declareBackgroundMatchingListenerViaJNI(env, class, advanced_publisher_ptr, callback, on_close)
    private external fun declareBackgroundMatchingListenerViaJNI(ptr: Long, callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback)
    // Rust: Java_io_zenoh_jni_JNIAdvancedPublisher_getMatchingStatusViaJNI(env, class, advanced_publisher_ptr) -> jboolean
    private external fun getMatchingStatusViaJNI(ptr: Long): Boolean
    // Rust: Java_io_zenoh_jni_JNIAdvancedPublisher_freePtrViaJNI(env, class, publisher_ptr)
    private external fun freePtrViaJNI(ptr: Long)
}
```

### `JNIAdvancedSubscriber.kt`
```kotlin
class JNIAdvancedSubscriber(val ptr: Long) {
    // CRITICAL: history Boolean required — matches Rust param `history: jboolean`
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

    // Rust: Java_io_zenoh_jni_JNIAdvancedSubscriber_declareDetectPublishersSubscriberViaJNI(env, class, advanced_subscriber_ptr, history, callback, on_close) -> ptr
    private external fun declareDetectPublishersSubscriberViaJNI(ptr: Long, history: Boolean, callback: JNISubscriberCallback, onClose: JNIOnCloseCallback): Long
    // Rust: Java_..._declareBackgroundDetectPublishersSubscriberViaJNI(env, class, advanced_subscriber_ptr, history, callback, on_close)
    private external fun declareBackgroundDetectPublishersSubscriberViaJNI(ptr: Long, history: Boolean, callback: JNISubscriberCallback, onClose: JNIOnCloseCallback)
    // Rust: Java_..._declareSampleMissListenerViaJNI(env, class, advanced_subscriber_ptr, callback, on_close) -> ptr
    private external fun declareSampleMissListenerViaJNI(ptr: Long, callback: JNISampleMissListenerCallback, onClose: JNIOnCloseCallback): Long
    // Rust: Java_..._declareBackgroundSampleMissListenerViaJNI(env, class, advanced_subscriber_ptr, callback, on_close)
    private external fun declareBackgroundSampleMissListenerViaJNI(ptr: Long, callback: JNISampleMissListenerCallback, onClose: JNIOnCloseCallback)
    // Rust: Java_io_zenoh_jni_JNIAdvancedSubscriber_freePtrViaJNI(env, class, subscriber_ptr)
    private external fun freePtrViaJNI(ptr: Long)
}
```

### `JNIMatchingListener.kt`
```kotlin
class JNIMatchingListener(val ptr: Long) {
    fun close() { freePtrViaJNI(ptr) }
    // Rust: Java_io_zenoh_jni_JNIMatchingListener_freePtrViaJNI(env, class, matching_listener_ptr)
    private external fun freePtrViaJNI(ptr: Long)
}
```

### `JNISampleMissListener.kt`
```kotlin
class JNISampleMissListener(val ptr: Long) {
    fun close() { freePtrViaJNI(ptr) }
    // Rust: Java_io_zenoh_jni_JNISampleMissListener_freePtrViaJNI(env, class, sample_miss_listener_ptr)
    private external fun freePtrViaJNI(ptr: Long)
}
```

### `callbacks/JNIMatchingListenerCallback.kt`
```kotlin
fun interface JNIMatchingListenerCallback {
    fun run(matching: Boolean)
}
```
(Rust calls `env.call_method(..., "run", "(Z)V", &[JValue::from(matching_status.matching())])`)

### `callbacks/JNISampleMissListenerCallback.kt`
```kotlin
fun interface JNISampleMissListenerCallback {
    fun run(zidLower: Long, zidUpper: Long, eid: Long, nb: Long)
}
```
(Rust calls `env.call_method(..., "run", "(JJJJ)V", &[zid_lower, zid_upper, eid as i64, missed_count as i64])`)

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
Add explicit `ZenohLoad` reference before JNI call to prevent `UnsatisfiedLinkError` when `Logger.start()` is called before any other JNI class is initialized:
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

**`Session.kt`**: Inline callback assembly previously in `JNISession.kt`:
- `declarePublisher(keyExpr, options)` → calls `jniSession.declarePublisherViaJNI(keyExpr.jniKeyExpr?.ptr ?: 0, keyExpr.keyExpr, jniSession.sessionPtr, ...)`, wraps result `Long` in `Publisher(keyExpr, ..., JNIPublisher(ptr))`
- `declareSubscriberWithHandler/WithCallback(...)` → creates `JNISubscriberCallback { ke, payload, encodingId, ... -> Sample(KeyExpr(ke, null), payload.into(), ...) }` inline (moved from JNISession), calls `jniSession.declareSubscriberViaJNI(...)`, wraps in `HandlerSubscriber`/`CallbackSubscriber`
- `declareQueryableWith*(...)` → creates `JNIQueryableCallback { ... -> Query(...) }` inline, calls `jniSession.declareQueryableViaJNI(...)`, wraps
- `declareQuerier(...)` → calls `jniSession.declareQuerierViaJNI(...)`, wraps in `Querier`
- `performGet*(...)` → creates `JNIGetCallback { ... -> Reply.Success/Error(...) }` inline, calls `jniSession.getViaJNI(...)`
- `zid/peersZid/routersZid` → calls JNI methods, wraps `ByteArray` → `ZenohId`
- `declareKeyExpr/undeclareKeyExpr` → calls JNI methods, wraps `Long` → `KeyExpr`
- `performPut/performDelete` → calls `jniSession.putViaJNI(...)`/`jniSession.deleteViaJNI(...)` with primitives

**`Config.kt`**: Update factory methods to wrap Long from runtime:
- `companion object { fun default(): Config { return Config(JNIConfig(JNIConfig.loadDefaultConfig())) } }`

**`KeyExpr.kt`**: Update to use String from runtime:
- `JNIKeyExpr.tryFrom(keyExpr)` now returns `String` → wrap: `KeyExpr(JNIKeyExpr.tryFrom(keyExpr), null)`
- Comparison methods: pass `(keyExprA.jniKeyExpr?.ptr ?: 0, keyExprA.keyExpr, keyExprB.jniKeyExpr?.ptr ?: 0, keyExprB.keyExpr)` to runtime methods

**`Publisher.kt`**: `put(IntoZBytes, Encoding?, IntoZBytes?)` decomposes to primitives and calls `jniPublisher.put(payload.into().bytes, encoding.id, encoding.schema, attachment?.into()?.bytes)`

**`Query.kt`**: `replySuccess(sample: Sample)` decomposes sample, calls `jniQuery.replySuccessViaJNI(ptr, keyExprPtr, keyExprStr, payload, encodingId, ...)`

**`Zenoh.kt`** (scouting): Scout methods build inline `JNIScoutCallback { whatAmI2: Int, id: ByteArray, locators: List<String> -> callback.run(Hello(WhatAmI.fromInt(whatAmI2), ZenohId(id), locators)) }`, call `JNIScout.scout(binaryWhatAmI, scoutCallback, onClose, configPtr)`, wrap returned `Long` in `JNIScout(ptr)` then in `HandlerScout`/`CallbackScout`

**`Liveliness.kt`**: Pass keyExpr as `(sessionPtr, keyExprPtr, keyExprStr)` primitives to runtime `JNILiveliness`; wrap returned `Long` in `LivelinessToken(JNILivelinessToken(ptr))`, `CallbackSubscriber(keyExpr, JNISubscriber(ptr))`, etc.

**`Querier.kt`**: `performGet(keyExpr, ...)` creates `JNIGetCallback { ... -> Reply(...) }` inline, calls `jniQuerier.getViaJNI(ptr, keyExprPtr, keyExprStr, params, callback, onClose, attachmentBytes, payloadBytes, encodingId, encodingSchema)`

---

## Adversarial Issues Resolution

| Issue | Resolution |
|-------|------------|
| `ZenohLoad` `internal` across modules | `ZenohLoad` is `public` in zenoh-jni-runtime |
| `Target.kt` missing from plan | Explicitly moved to `zenoh-jni-runtime/src/jvmMain/` |
| `JNIConfig`/`JNIKeyExpr` companion binding preservation | Companion WITHOUT `@JvmStatic` explicitly specified — preserves `_00024Companion_` JNI symbol |
| Advanced adapter JNI pattern mismatch | All follow `JNIPublisher` pattern: `private external fun` with explicit `ptr: Long` last param |
| `detect-publishers history` param missing | `declareDetectPublishersSubscriber(history: Boolean, ...)` explicitly includes it |
| `JNIZBytes`/`Logger` facade dependency | `JNIZBytes` stays in zenoh-java; `Logger.kt` adds `ZenohLoad` reference before external call |
| Scouting `_00024Companion_` preserved | `JNIScout` companion WITHOUT `@JvmStatic` on `scoutViaJNI` |
| Build: local + remote + Android | `zenoh-jni-runtime/build.gradle.kts` copies all three packaging patterns from zenoh-java |
| New public zenoh-java API (AdvancedPublisher etc.) | Out of scope — runtime only adds JNI adapters; zenoh-java's public API extension is a separate concern |

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
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIPublisher.kt` | New — public val ptr, primitive put/delete |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIConfig.kt` | New — factory methods return Long |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIKeyExpr.kt` | New — factory methods return String |
| `zenoh-jni-runtime/src/commonMain/.../jni/JNIQuery.kt` | New — public primitive externals, no facade wrappers |
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
| `zenoh-java/src/commonMain/.../Session.kt` | Inline callback assembly + facade wrapping |
| `zenoh-java/src/commonMain/.../Config.kt` | Wrap Long → Config |
| `zenoh-java/src/commonMain/.../keyexpr/KeyExpr.kt` | Wrap String primitives |
| `zenoh-java/src/commonMain/.../pubsub/Publisher.kt` | Decompose IntoZBytes/Encoding → bytes |
| `zenoh-java/src/commonMain/.../query/Query.kt` | Decompose Sample → primitives |
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
6. Verify `JNIAdvancedPublisher`/`JNIAdvancedSubscriber` parameter counts match Rust exports exactly (checked against source)

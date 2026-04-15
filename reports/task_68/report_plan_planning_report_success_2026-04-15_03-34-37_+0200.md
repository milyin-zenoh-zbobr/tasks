# Plan: Create `zenoh-jni-runtime` Module (Kotlin Layer)

## Context

The Rust JNI exports for advanced pub/sub are already done on the work branch (task 68):
- `zenoh-jni/src/ext/advanced_publisher.rs`, `advanced_subscriber.rs`, `matching_listener.rs`, `sample_miss_listener.rs`
- `session.rs` updated with `declareAdvancedSubscriberViaJNI` / `declareAdvancedPublisherViaJNI`
- `openSessionViaJNI` unified symbol (no Companion prefix, via `@JvmStatic`)
- Scouting still uses Companion prefix: `Java_io_zenoh_jni_JNIScout_00024Companion_scoutViaJNI`

The remaining work is Kotlin-side: creating a `zenoh-jni-runtime` Gradle subproject that both `zenoh-java` and (in the future) `zenoh-kotlin`) can depend on, containing only the primitive-only JNI adapters.

**Existing analog**: `JNIPublisher.kt` — instance class stores `private val ptr: Long`, declares `private external fun` with ptr as explicit last parameter, public methods call private externals passing `this.ptr`.

---

## JNI Binding Pattern (Critical Constraint)

All Kotlin adapter classes in `zenoh-jni-runtime` MUST follow the `JNIPublisher` pattern:
1. Store `val ptr: Long` in the class instance
2. Declare `private external fun` with all Rust parameters (excluding JNIEnv, JClass which are implicit)
3. Public wrapper methods call private externals passing `this.ptr`

The Rust exports are **static JNI** (take `_class: JClass`), NOT true instance methods. Declaring them as Kotlin `external fun` inside a class with no explicit ptr would generate the wrong JNI symbol shape and cause `UnsatisfiedLinkError`.

---

## Step 1: Create `zenoh-jni-runtime` Gradle Subproject

### 1a. `settings.gradle.kts`
Add: `include(":zenoh-jni-runtime")`

### 1b. `zenoh-jni-runtime/build.gradle.kts`
Copy and adapt from `zenoh-java/build.gradle.kts`:
- Multiplatform Kotlin (JVM + optional Android targets)
- Owns `buildZenohJni` Gradle task pointing to `../zenoh-jni/Cargo.toml`
- Native lib resources:
  - Local (non-remote): `../zenoh-jni/target/{debug|release}` (*.dylib, *.so, *.dll)
  - Remote publication (`isRemotePublication=true`): `../jni-libs` (preserve existing CI behavior)
  - Android: `rust-android-gradle` plugin, same cargo cross-compilation targets as zenoh-java
- Published as `org.eclipse.zenoh:zenoh-jni-runtime`
- **No** kotlin-serialization, dokka, guava, commons-net (those are facade concerns)

### 1c. ZenohLoad — move to `zenoh-jni-runtime`
- `commonMain/kotlin/io/zenoh/ZenohLoad.kt`: `internal expect object ZenohLoad`
- `jvmMain/kotlin/io/zenoh/ZenohLoad.kt`: copy full `actual object ZenohLoad` from zenoh-java's `jvmMain/Zenoh.kt`
- `androidMain/kotlin/io/zenoh/ZenohLoad.kt`: copy `actual object ZenohLoad { System.loadLibrary("zenoh_jni") }` from zenoh-java

---

## Step 2: Move/Refactor JNI Adapters into `zenoh-jni-runtime`

**Constraint**: Zero imports of `io.zenoh.*` facade types. Only primitives, `ByteArray`, `Long`, `String`, `Boolean`, `Int`, and callback interfaces.

### 2a. Classes moved with visibility change only (`internal` → `public`):
- `JNISubscriber.kt`, `JNIQueryable.kt`, `JNILivelinessToken.kt`, `JNIZenohId.kt`
- `callbacks/JNISubscriberCallback.kt`, `JNIQueryableCallback.kt`, `JNIGetCallback.kt`, `JNIScoutCallback.kt`, `JNIOnCloseCallback.kt`

### 2b. Classes requiring refactoring (remove facade-type references):

**`JNISession.kt`**:
- All external funs become `public`
- Keep `@JvmStatic` on `openSessionViaJNI` (matches unified Rust symbol, no Companion prefix)
- Add new public external fun declarations matching session.rs Rust exports:
  - `declareAdvancedSubscriberViaJNI(keyExprPtr, keyExprStr, sessionPtr, historyEnabled, detectLatePublishers, maxSamples, maxAgeSeconds, recoveryEnabled, isHeartbeat, queryPeriodMs, subscriberDetection, callback, onClose): Long`
  - `declareAdvancedPublisherViaJNI(keyExprPtr, keyExprStr, sessionPtr, congestionControl, priority, isExpress, reliability, cacheEnabled, cacheMaxSamples, cacheRepliesPriority, cacheRepliesCongestionControl, cacheRepliesIsExpress, missDetectionEnabled, missDetectionHeartbeat, heartbeatMs, heartbeatIsSporadic, publisherDetection): Long`
- Remove all high-level facade wrapper methods; callback assembly moves to zenoh-java's `Session.kt`

**`JNIPublisher.kt`**:
- Change `private val ptr` → `public val ptr`
- Expose `put(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?)` and `delete(attachment: ByteArray?)` as public (decomposition of IntoZBytes/Encoding moves to `Publisher.kt` in zenoh-java)
- External funs stay private
- Remove `import io.zenoh.bytes.Encoding`, `import io.zenoh.bytes.IntoZBytes`

**`JNIConfig.kt`**:
- Factory methods return `Long` instead of `Config`
- Config wrapping moves to zenoh-java's `Config.kt`

**`JNIKeyExpr.kt`**:
- Factory methods return `String` instead of `KeyExpr`
- Comparison/join/concat methods take raw `(ptrA: Long, strA: String, ...)` instead of KeyExpr facades

**`JNIQuery.kt`**:
- Expose external funs directly (already primitive)
- Remove `replySuccess(sample: Sample)` wrapper — decomposition moves to zenoh-java's `Query.kt`

**`JNIQuerier.kt`**:
- `performGet*` takes `(keyExprPtr: Long, keyExprStr: String, ...)` instead of `KeyExpr`
- Remove Reply construction (moves to zenoh-java)

**`JNIScout.kt`** (CRITICAL — preserve Companion prefix):
- Keep `companion object` WITHOUT `@JvmStatic` on `scoutViaJNI`
- This preserves `_00024Companion_` JNI symbol matching Rust: `Java_io_zenoh_jni_JNIScout_00024Companion_scoutViaJNI`
- Remove Hello/HandlerScout/CallbackScout facade construction (moves to zenoh-java)

**`JNILiveliness.kt`**:
- All methods take `(keyExprPtr: Long, keyExprStr: String)` instead of KeyExpr
- Return raw Long handles instead of facade objects

### 2c. Classes that stay in `zenoh-java` (NOT moved to runtime):
- **`JNIZBytes.kt`**: Returns `ZBytes` facade type from external fun — violates primitive-only constraint. zenoh-kotlin has its own serialization; only zenoh-java needs it.
- **`Logger.kt`**: `startLogsViaJNI` is bound to `io.zenoh.Logger` class in zenoh-java.

---

## Step 3: New Files in Runtime (Advanced Pub/Sub Adapters)

All follow the `JNIPublisher` pattern: store `val ptr: Long`, `private external fun` with explicit ptr as parameter, public wrapper methods.

### `JNIAdvancedPublisher.kt`
```
class JNIAdvancedPublisher(val ptr: Long) {
    // Public wrapper methods:
    fun put(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?)
    fun delete(attachment: ByteArray?)
    fun declareMatchingListener(callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback): Long
    fun declareBackgroundMatchingListener(callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback)
    fun getMatchingStatus(): Boolean
    fun close()  // calls freePtrViaJNI(ptr)

    // Private external funs — EXACT parameter order matches Rust (excluding JNIEnv, JClass):
    // Rust: Java_..._putViaJNI(payload, encoding_id, encoding_schema, attachment, publisher_ptr)
    private external fun putViaJNI(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?, ptr: Long)
    // Rust: Java_..._deleteViaJNI(attachment, publisher_ptr)
    private external fun deleteViaJNI(attachment: ByteArray?, ptr: Long)
    // Rust: Java_..._declareMatchingListenerViaJNI(advanced_publisher_ptr, callback, on_close)
    private external fun declareMatchingListenerViaJNI(ptr: Long, callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback): Long
    // Rust: Java_..._declareBackgroundMatchingListenerViaJNI(advanced_publisher_ptr, callback, on_close)
    private external fun declareBackgroundMatchingListenerViaJNI(ptr: Long, callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback)
    // Rust: Java_..._getMatchingStatusViaJNI(advanced_publisher_ptr)
    private external fun getMatchingStatusViaJNI(ptr: Long): Boolean
    // Rust: Java_..._freePtrViaJNI(publisher_ptr)
    private external fun freePtrViaJNI(ptr: Long)
}
```

### `JNIAdvancedSubscriber.kt`
```
class JNIAdvancedSubscriber(val ptr: Long) {
    // Public wrapper methods:
    fun declareDetectPublishersSubscriber(history: Boolean, callback: JNISubscriberCallback, onClose: JNIOnCloseCallback): Long
    fun declareBackgroundDetectPublishersSubscriber(history: Boolean, callback: JNISubscriberCallback, onClose: JNIOnCloseCallback)
    fun declareSampleMissListener(callback: JNISampleMissListenerCallback, onClose: JNIOnCloseCallback): Long
    fun declareBackgroundSampleMissListener(callback: JNISampleMissListenerCallback, onClose: JNIOnCloseCallback)
    fun close()  // calls freePtrViaJNI(ptr)

    // Private external funs — CRITICAL: history Boolean required for detect-publishers methods
    // Rust: Java_..._declareDetectPublishersSubscriberViaJNI(advanced_subscriber_ptr, history, callback, on_close)
    private external fun declareDetectPublishersSubscriberViaJNI(ptr: Long, history: Boolean, callback: JNISubscriberCallback, onClose: JNIOnCloseCallback): Long
    // Rust: Java_..._declareBackgroundDetectPublishersSubscriberViaJNI(advanced_subscriber_ptr, history, callback, on_close)
    private external fun declareBackgroundDetectPublishersSubscriberViaJNI(ptr: Long, history: Boolean, callback: JNISubscriberCallback, onClose: JNIOnCloseCallback)
    // Rust: Java_..._declareSampleMissListenerViaJNI(advanced_subscriber_ptr, callback, on_close)
    private external fun declareSampleMissListenerViaJNI(ptr: Long, callback: JNISampleMissListenerCallback, onClose: JNIOnCloseCallback): Long
    // Rust: Java_..._declareBackgroundSampleMissListenerViaJNI(advanced_subscriber_ptr, callback, on_close)
    private external fun declareBackgroundSampleMissListenerViaJNI(ptr: Long, callback: JNISampleMissListenerCallback, onClose: JNIOnCloseCallback)
    // Rust: Java_..._freePtrViaJNI(subscriber_ptr)
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
fun interface JNIMatchingListenerCallback { fun run(matching: Boolean) }
```
(Rust calls `env.call_method(..., "run", "(Z)V", &[JValue::from(matching)])`)

### `callbacks/JNISampleMissListenerCallback.kt`
```kotlin
fun interface JNISampleMissListenerCallback { fun run(zidLower: Long, zidUpper: Long, eid: Long, nb: Long) }
```
(Rust calls `env.call_method(..., "run", "(JJJJ)V", &[zid_lower, zid_upper, eid, missed_count])`)

---

## Step 4: Refactor `zenoh-java` to Use Runtime

### 4a. `zenoh-java/build.gradle.kts`:
- Remove `buildZenohJni` task and `buildZenohJNI` function (moved to runtime)
- Remove native lib resources from jvmMain/jvmTest (packaged by runtime)
- Add: `implementation(project(":zenoh-jni-runtime"))`
- Keep all other dependencies (commons-net, guava, serialization)
- Keep `jvmArgs("-Djava.library.path=../zenoh-jni/target/$buildMode")` for tests

### 4b. Remove ZenohLoad expect/actual from `zenoh-java` (commonMain, jvmMain, androidMain)

### 4c. `zenoh-java/src/commonMain/kotlin/io/zenoh/Logger.kt`:
Add explicit runtime loading before JNI call (resolves Logger-before-load race):
```kotlin
fun start(filter: String) {
    ZenohLoad  // forces native library to load (ZenohLoad is in zenoh-jni-runtime)
    startLogsViaJNI(filter)
}
```

### 4d. Delete from `zenoh-java/src/` (moved to runtime):
All `io.zenoh.jni.*` files EXCEPT `JNIZBytes.kt`

### 4e. Update facade classes with callback assembly (was in JNISession):
- **`Session.kt`**: Inline `JNISubscriberCallback`, `JNIQueryableCallback`, `JNIGetCallback` lambda assembly; call runtime primitives; add `declareAdvancedSubscriber()` / `declareAdvancedPublisher()` methods wrapping `JNIAdvancedSubscriber` / `JNIAdvancedPublisher`
- **`Config.kt`**: Wrap `Long` → `Config` from runtime `JNIConfig`
- **`KeyExpr.kt`**: Wrap `String` from runtime `JNIKeyExpr`
- **`Publisher.kt`**: `put()` decomposes `IntoZBytes`/`Encoding` to bytes, calls `jniPublisher.put(bytes, ...)`
- **`Query.kt`**: `reply*()` decomposes `Sample` to primitives, calls runtime `JNIQuery`
- **`Zenoh.kt`**: Scout methods inline `JNIScoutCallback` assembly; wrap `Long` → `HandlerScout`/`CallbackScout`
- **`Liveliness.kt`**: Pass keyExpr as `(ptr, str)` primitives; wrap returned `Long` in facade objects

---

## Critical Files

| File | Change |
|------|--------|
| `settings.gradle.kts` | Add `include(":zenoh-jni-runtime")` |
| `zenoh-jni-runtime/build.gradle.kts` | New — copy from zenoh-java build with native packaging |
| `zenoh-jni-runtime/src/.../ZenohLoad.kt` | New — moved from zenoh-java |
| `zenoh-jni-runtime/src/.../jni/JNISession.kt` | New — public externals, no facade types |
| `zenoh-jni-runtime/src/.../jni/JNIPublisher.kt` | New — public, primitive-only |
| `zenoh-jni-runtime/src/.../jni/JNIConfig.kt` | New — factory methods return Long |
| `zenoh-jni-runtime/src/.../jni/JNIKeyExpr.kt` | New — factory methods return String |
| `zenoh-jni-runtime/src/.../jni/JNIQuery.kt` | New — primitive-only externals |
| `zenoh-jni-runtime/src/.../jni/JNIQuerier.kt` | New — primitive keyexpr params |
| `zenoh-jni-runtime/src/.../jni/JNIScout.kt` | New — companion WITHOUT @JvmStatic |
| `zenoh-jni-runtime/src/.../jni/JNILiveliness.kt` | New — primitive keyexpr |
| `zenoh-jni-runtime/src/.../jni/JNIAdvancedPublisher.kt` | New — see exact signatures above |
| `zenoh-jni-runtime/src/.../jni/JNIAdvancedSubscriber.kt` | New — see exact signatures above |
| `zenoh-jni-runtime/src/.../jni/JNIMatchingListener.kt` | New |
| `zenoh-jni-runtime/src/.../jni/JNISampleMissListener.kt` | New |
| `zenoh-jni-runtime/src/.../jni/callbacks/JNIMatchingListenerCallback.kt` | New — `fun run(Boolean)` |
| `zenoh-jni-runtime/src/.../jni/callbacks/JNISampleMissListenerCallback.kt` | New — `fun run(Long, Long, Long, Long)` |
| `zenoh-java/build.gradle.kts` | Remove Rust build task, add runtime dep |
| `zenoh-java/src/.../Logger.kt` | Add ZenohLoad reference before startLogsViaJNI |
| `zenoh-java/src/.../Session.kt` | Add facade assembly; add advanced pub/sub methods |
| `zenoh-java/src/.../Config.kt` | Wrap Long → Config |
| `zenoh-java/src/.../keyexpr/KeyExpr.kt` | Wrap String primitives |
| `zenoh-java/src/.../jni/` (all except JNIZBytes.kt) | Delete |

---

## Verification

1. `./gradlew :zenoh-jni-runtime:build` — compiles without any `io.zenoh.*` facade imports
2. `./gradlew :zenoh-java:test` — all existing tests pass
3. `grep -r "^import io\.zenoh\." zenoh-jni-runtime/src/` — zero results (only `io.zenoh.jni.*` and `io.zenoh.ZenohLoad` allowed)
4. `grep -r "ZenohLoad\|System.load" zenoh-java/src/commonMain/` — only Logger.kt reference
5. Run ZPub/ZSub/ZGet/ZQueryable examples end-to-end
6. Verify `JNIAdvancedPublisher`/`JNIAdvancedSubscriber` external fun parameter counts/types match Rust exports exactly

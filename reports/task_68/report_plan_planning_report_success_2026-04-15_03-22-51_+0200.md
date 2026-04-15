# Plan: Kotlin JNI Adapter Layer for zenoh-jni-runtime

## Context

The Rust side is already complete on the work branch (task 68):
- New Rust JNI exports: `JNIAdvancedPublisher`, `JNIAdvancedSubscriber`, `JNIMatchingListener`, `JNISampleMissListener`
- New session exports: `declareAdvancedSubscriberViaJNI`, `declareAdvancedPublisherViaJNI`
- `openSessionViaJNI` unified (no Companion prefix, via `@JvmStatic`)
- Scouting still uses `Companion` prefix: `Java_io_zenoh_jni_JNIScout_00024Companion_scoutViaJNI`

This plan covers the Kotlin side: creating a `zenoh-jni-runtime` Gradle subproject that both zenoh-java and (in the future) zenoh-kotlin can depend on.

---

## Architecture

```
zenoh-kotlin (future, separate repo)
zenoh-java
    ↓ both depend on
zenoh-jni-runtime   ← new subproject
    ├── io.zenoh.jni.*         (JNI adapters, primitive-only public API)
    ├── io.zenoh.jni.callbacks (callback interfaces)
    ├── io.zenoh.ZenohLoad     (library loading, expect/actual)
    └── owns zenoh-jni Rust build
```

---

## Step 1: Create `zenoh-jni-runtime` Gradle Subproject

### 1a. `settings.gradle.kts`
Add: `include(":zenoh-jni-runtime")`

### 1b. `zenoh-jni-runtime/build.gradle.kts`
Copy structure from `zenoh-java/build.gradle.kts`:
- Multiplatform (jvm + optional androidTarget)
- Owns `buildZenohJni` task pointing to `../zenoh-jni/Cargo.toml`
- Native lib resources:
  - Local: `../zenoh-jni/target/$buildMode` (*.dylib, *.so, *.dll)
  - Remote publication (`isRemotePublication=true`): `../jni-libs` (preserve existing CI behavior)
  - Android: cargo integration via `rust-android-gradle` plugin (copy from zenoh-java)
- Published as `org.eclipse.zenoh:zenoh-jni-runtime`
- No dokka, no kotlin-serialization, no commons-net/guava

### 1c–1e. ZenohLoad expect/actual
- `commonMain`: `internal expect object ZenohLoad`
- `jvmMain`: Copy full `actual object ZenohLoad` from `zenoh-java/src/jvmMain/kotlin/io/zenoh/Zenoh.kt`
- `androidMain`: Copy `actual object ZenohLoad { System.loadLibrary("zenoh_jni") }` from zenoh-java

---

## Step 2: Move/Refactor JNI Adapters into Runtime

**Key principle**: All classes in the runtime must have zero imports of facade types. Only primitives, ByteArray, Long, String, Boolean, Int, and callback interfaces permitted.

### 2a. Classes moved as-is (change visibility only):
- `JNISubscriber.kt`, `JNIQueryable.kt`, `JNILivelinessToken.kt`, `JNIZenohId.kt`
- All callbacks: `JNISubscriberCallback.kt`, `JNIQueryableCallback.kt`, `JNIGetCallback.kt`, `JNIScoutCallback.kt`, `JNIOnCloseCallback.kt`

### 2b. Classes requiring refactoring:

**`JNISession.kt`**:
- All external funs become public (previously private)
- Keep `@JvmStatic` on `openSessionViaJNI` (matches unified Rust symbol, no Companion prefix)
- Add new external fun declarations:
  - `declareAdvancedSubscriberViaJNI(keyExprPtr, keyExprStr, sessionPtr, historyEnabled, detectLatePublishers, maxSamples, maxAgeSeconds, recoveryEnabled, isHeartbeat, queryPeriodMs, subscriberDetection, callback, onClose): Long`
  - `declareAdvancedPublisherViaJNI(keyExprPtr, keyExprStr, sessionPtr, congestionControl, priority, isExpress, reliability, cacheEnabled, cacheMaxSamples, cacheRepliesPriority, cacheRepliesCongestionControl, cacheRepliesIsExpress, missDetectionEnabled, missDetectionHeartbeat, heartbeatMs, heartbeatIsSporadic, publisherDetection): Long`
- Remove all facade-type references; callback assembly moves to zenoh-java

**`JNIPublisher.kt`**:
- Expose external funs `putViaJNI(ByteArray, Int, String?, ByteArray?, Long)` and `deleteViaJNI(ByteArray?, Long)` as public
- Remove `put(IntoZBytes, Encoding?, IntoZBytes?)` wrapper (moves to zenoh-java's `Publisher.kt`)

**`JNIConfig.kt`**:
- Factory methods return `Long` instead of `Config`
- Config wrapping moves to zenoh-java

**`JNIKeyExpr.kt`**:
- Factory methods return `String` instead of `KeyExpr`
- Remove all KeyExpr imports

**`JNIQuery.kt`**:
- Expose external funs directly (already primitives)
- Remove `replySuccess(sample: Sample)` wrapper (moves to zenoh-java)

**`JNIQuerier.kt`**:
- `performGet*` takes `(keyExprPtr: Long, keyExprStr: String, ...)` instead of `KeyExpr`
- Remove Reply construction

**`JNIScout.kt`** (CRITICAL — scouting Companion prefix):
- Keep `companion object` WITHOUT `@JvmStatic` on `scoutViaJNI`
- This preserves the `_00024Companion_` JNI symbol matching Rust: `Java_io_zenoh_jni_JNIScout_00024Companion_scoutViaJNI`
- Remove Hello/HandlerScout/CallbackScout construction (moves to zenoh-java)

**`JNILiveliness.kt`**:
- All methods take `(keyExprPtr: Long, keyExprStr: String)` instead of KeyExpr
- Return raw Long handles instead of facade objects

### 2c. Excluded from runtime (stay in zenoh-java):
- **`JNIZBytes.kt`**: Returns `ZBytes` facade type from external fun — cannot be primitive-only. zenoh-kotlin has its own serialization and doesn't need this.
- **`Logger.kt`**: `startLogsViaJNI` external fun is bound to `io.zenoh.Logger` class in zenoh-java.

---

## Step 3: New Files in Runtime (Advanced Pub/Sub)

**`JNIAdvancedPublisher.kt`** — instance class with `val ptr: Long`:
- `external fun putViaJNI(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?)`
- `external fun deleteViaJNI(attachment: ByteArray?)`
- `external fun declareMatchingListenerViaJNI(callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback): Long`
- `external fun declareBackgroundMatchingListenerViaJNI(callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback)`
- `external fun getMatchingStatusViaJNI(): Boolean`
- `external fun freePtrViaJNI()`

**`JNIAdvancedSubscriber.kt`** — instance class with `val ptr: Long`:
- `external fun declareDetectPublishersSubscriberViaJNI(callback: JNISubscriberCallback, onClose: JNIOnCloseCallback): Long`
- `external fun declareBackgroundDetectPublishersSubscriberViaJNI(callback: JNISubscriberCallback, onClose: JNIOnCloseCallback)`
- `external fun declareSampleMissListenerViaJNI(callback: JNISampleMissListenerCallback, onClose: JNIOnCloseCallback): Long`
- `external fun declareBackgroundSampleMissListenerViaJNI(callback: JNISampleMissListenerCallback, onClose: JNIOnCloseCallback)`
- `external fun freePtrViaJNI()`

**`JNIMatchingListener.kt`**: `class JNIMatchingListener(val ptr: Long) { external fun freePtrViaJNI() }`

**`JNISampleMissListener.kt`**: `class JNISampleMissListener(val ptr: Long) { external fun freePtrViaJNI() }`

**`callbacks/JNIMatchingListenerCallback.kt`**:
```kotlin
fun interface JNIMatchingListenerCallback { fun run(matching: Boolean) }
```
(matches Rust: `env.call_method(..., "run", "(Z)V", ...)`)

**`callbacks/JNISampleMissListenerCallback.kt`**:
```kotlin
fun interface JNISampleMissListenerCallback { fun run(zidLower: Long, zidUpper: Long, eid: Long, nb: Long) }
```
(matches Rust: `env.call_method(..., "run", "(JJJJ)V", ...)`)

---

## Step 4: Refactor `zenoh-java` to Use Runtime

### 4a. `zenoh-java/build.gradle.kts`:
- Remove `buildZenohJni` task and `buildZenohJNI` function
- Remove native lib resources from jvmMain/jvmTest
- Add: `implementation(project(":zenoh-jni-runtime"))`
- Keep all other dependencies
- Keep `jvmArgs("-Djava.library.path=../zenoh-jni/target/$buildMode")` for tests

### 4b–4d. Remove ZenohLoad expect/actual from zenoh-java (commonMain, jvmMain, androidMain)

### 4e. `zenoh-java/src/commonMain/kotlin/io/zenoh/Logger.kt`:
- Add ZenohLoad reference before JNI call (resolves adversarial issue #2):
```kotlin
fun start(filter: String) {
    ZenohLoad  // triggers runtime library loading
    startLogsViaJNI(filter)
}
```

### 4f. Delete from zenoh-java (moved to runtime):
All `io.zenoh.jni.*` files except `JNIZBytes.kt`

### 4g. Update facade classes:
- **`Session.kt`**: Inline callback assembly (was in JNISession); call runtime methods with primitives; add `declareAdvancedSubscriber`/`declareAdvancedPublisher` methods
- **`Config.kt`**: Wrap Long → Config from runtime JNIConfig
- **`KeyExpr.kt`**: Wrap String from runtime JNIKeyExpr
- **`Publisher.kt`**: `put()` decomposes IntoZBytes/Encoding to bytes, calls `jniPublisher.putViaJNI(...)`
- **`Query.kt`**: `reply*()` decomposes Sample to primitives, calls runtime JNIQuery
- **`Zenoh.kt`**: Scout methods inline JNIScoutCallback assembly; wrap Long → HandlerScout/CallbackScout
- **`Liveliness.kt`**: Pass keyExpr as (ptr, str) primitives; wrap returned Long in facade objects

---

## Adversarial Issues Resolution

| Issue | Resolution |
|-------|------------|
| JNIPublisher/JNIZBytes depend on facade types | JNIZBytes stays in zenoh-java; JNIPublisher exposes raw external funs; facade wrapping moves to Publisher.kt |
| Logger.start() before library load | Logger.start() explicitly references ZenohLoad (from runtime) before calling startLogsViaJNI |
| Scouting Companion prefix in Rust | JNIScout.companion does NOT add @JvmStatic to scoutViaJNI → preserves `_00024Companion_` symbol |
| Build: local + remote + Android packaging | zenoh-jni-runtime build.gradle.kts copies all three packaging patterns from zenoh-java |

---

## Verification

1. `./gradlew :zenoh-jni-runtime:build` — runtime compiles without any `io.zenoh.*` facade imports
2. `./gradlew :zenoh-java:test` — all existing tests pass
3. `grep -r "^import io\.zenoh\." zenoh-jni-runtime/src/` — zero results (only `io.zenoh.jni.*` and `io.zenoh.ZenohLoad` allowed)
4. `grep -r "ZenohLoad\|System.load" zenoh-java/src/commonMain/` — zero (loading fully in runtime)
5. Run ZPub/ZSub/ZGet/ZQueryable examples end-to-end
6. Verify `JNIAdvancedPublisher`/`JNIAdvancedSubscriber` Kotlin methods match `Java_io_zenoh_jni_JNIAdvancedPublisher_*` Rust symbols

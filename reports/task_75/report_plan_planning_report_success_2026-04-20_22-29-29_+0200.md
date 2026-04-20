# Plan: Throw Exceptions from Java — Full JNI Error Handling Refactor

## Context

**Problem:** `zenoh-jni-runtime` throws JVM exceptions from Rust via `throw_exception!` → `ZError::throw_on_jvm()`. The `zenoh-kotlin` library reuses `zenoh-jni-runtime` directly and wraps every JNI call in `runCatching`, which is inconvenient.

**Goal:**
- Rust JNI functions never throw JVM exceptions. Instead: they accept an `error: Array<String?>` out-parameter (last parameter), return a sentinel value on failure, and write the error message into `error[0]`.
- `ZError.kt` is removed from `zenoh-jni-runtime` and added to `zenoh-java`.
- Exception throwing (`throw ZError(...)`) lives only at the `zenoh-java` API layer.

**Scope corrections vs prior plan:** The previous plan incorrectly excluded zbytes/zbytes_kotlin paths, the async callback path in utils.rs, and was missing call sites for JNIZenohId.kt, ZenohId.kt, Zenoh.kt, ZDeserializer.kt, ZSerializer.kt. It also missed key_expr.rs, publisher.rs, querier.rs, scouting.rs, logger.rs, zenoh_id.rs, advanced_subscriber.rs from the Rust inventory. Total: 55 throw_exception! calls across 15 Rust files.

---

## Error-indicator conventions (new JNI API)

| Return type | Error indicator | Success |
|---|---|---|
| `jlong` (pointer) | `0L` | raw pointer cast to jlong |
| `jobject` / `jbyteArray` | null (`JObject::null().as_raw()`) | valid object |
| `jstring` | null | valid jstring |
| `jint` (formerly void or bool) | `-1` | `0` (void) or `0`/`1` (bool) |

`error_out: JObjectArray` is always the last parameter. On success it is not modified.

---

## Phase 1 — Rust `zenoh-jni/src/errors.rs`

- Add helper `pub(crate) fn set_error_string(env: &mut JNIEnv, error_out: &JObjectArray, msg: &str)` that writes `msg` into `error_out[0]`. Log JNI failures internally with `tracing::error!`.
- Remove `throw_on_jvm()` method and `KOTLIN_EXCEPTION_NAME` constant from `ZError`.
- Retain `ZError` struct, `zerror!` macro, `ZResult<T>` for internal Rust error propagation.
- The `throw_exception!` macro may be kept (unused) or removed.

---

## Phase 2 — Rust `zenoh-jni/src/utils.rs`

**Special case: async callback path.** The `load_on_close` function (lines 163–189) calls a Java `run()` callback from a daemon thread and currently throws on failure. Since this is an async context with no caller-owned out-parameter:
- Replace `throw_exception!(env, zerror!(...))` with `tracing::error!("Error while running 'onClose' callback: {}", err)` — log and return. No exception from Rust.

---

## Phase 3 — Rust JNI exported functions (all files)

Apply to all 54 `throw_exception!` call sites in exported functions across 14 files. For each:
1. Add `error_out: JObjectArray` as the last parameter
2. Change return type as per convention above
3. Replace every `throw_exception!(env, err); <sentinel>` with `set_error_string(&mut env, &error_out, &err.to_string()); <sentinel>`

### Exclude (free/close/undeclare — always succeed)
`undeclareKeyExprViaJNI` in session.rs (line 769), and all `free*ViaJNI`/`close*ViaJNI`/`undeclare*ViaJNI` variants.

### Files and functions to migrate

**`session.rs`** (16 exported fns with throw_exception!):
- `openSessionViaJNI` → jlong, error=0
- `openSessionWithJsonConfigViaJNI` → jlong, error=0 (no Kotlin wrapper exists but still exported; migrate to ensure Rust never resolves the ZError class)
- `openSessionWithYamlConfigViaJNI` → jlong, error=0 (same)
- `declarePublisherViaJNI` → jlong, error=0
- `putViaJNI` → jint, error=-1
- `deleteViaJNI` → jint, error=-1
- `declareSubscriberViaJNI` → jlong, error=0
- `declareQuerierViaJNI` → jlong, error=0
- `declareQueryableViaJNI` → jlong, error=0
- `declareKeyExprViaJNI` → jlong, error=0
- `getViaJNI` → jint, error=-1
- `getPeersZidViaJNI` → jobject, error=null
- `getRoutersZidViaJNI` → jobject, error=null
- `getZidViaJNI` → jbyteArray, error=null
- `declareAdvancedSubscriberViaJNI` → jlong, error=0
- `declareAdvancedPublisherViaJNI` → jlong, error=0

**`config.rs`** (5 calls + loadDefaultConfigViaJNI for uniformity):
- `loadDefaultConfigViaJNI` — add error_out for API uniformity → jlong, error=0
- `loadConfigFileViaJNI` → jlong, error=0
- `loadJsonConfigViaJNI` → jlong, error=0
- `loadYamlConfigViaJNI` → jlong, error=0
- `getJsonViaJNI` → jstring, error=null
- `insertJson5ViaJNI` → jint, error=-1

**`key_expr.rs`** (7 calls):
- `tryFromViaJNI`, `autocanonizeViaJNI`, `joinViaJNI`, `concatViaJNI` → jstring, error=null
- `intersectsViaJNI`, `includesViaJNI` → jint, error=-1 (formerly jboolean)
- `relationToViaJNI` → jint, error=-1

**`query.rs`** (3 calls):
- `replySuccessViaJNI`, `replyErrorViaJNI`, `replyDeleteViaJNI` → jint, error=-1

**`publisher.rs`** (2 calls):
- `putViaJNI`, `deleteViaJNI` → jint, error=-1

**`querier.rs`** (1 call):
- `getViaJNI` → jint, error=-1

**`scouting.rs`** (1 call):
- `scoutViaJNI` → jlong, error=0

**`logger.rs`** (1 call):
- `startLogsViaJNI` → jint, error=-1

**`zenoh_id.rs`** (1 call):
- `toStringViaJNI` → jstring, error=null

**`liveliness.rs`** (3 calls):
- `livelinessGetViaJNI` → jint, error=-1
- `declareLivelinessTokenViaJNI` → jlong, error=0
- `declareLivelinessSubscriberViaJNI` → jlong, error=0

**`ext/advanced_publisher.rs`** (5 calls):
- `putViaJNI`, `deleteViaJNI` → jint, error=-1
- `declareMatchingListenerViaJNI` → jlong, error=0
- `declareBackgroundMatchingListenerViaJNI` → jint, error=-1
- `getMatchingStatusViaJNI` → jint, error=-1 (formerly jboolean)

**`ext/advanced_subscriber.rs`** (4 calls):
- `declareDetectPublishersSubscriberViaJNI`, `declareSampleMissListenerViaJNI` → jlong, error=0
- `declareBackgroundDetectPublishersSubscriberViaJNI`, `declareBackgroundSampleMissListenerViaJNI` → jint, error=-1

**`zbytes.rs`** (2 calls):
- `serializeViaJNI`, `deserializeViaJNI` → jobject, error=null

**`zbytes_kotlin.rs`** (2 calls):
- `serializeViaJNI`, `deserializeViaJNI` → jobject, error=null

---

## Phase 4 — Kotlin `zenoh-jni-runtime`

### 4a. Delete `ZError.kt`
Remove `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`.

### 4b. Update all JNI adapter files

For every `external fun` whose Rust counterpart changed:
- Remove `@Throws(ZError::class)` annotation
- Add `error: Array<String?>` as last parameter
- Change return type: `Unit` → `Int`, `Boolean` → `Int`, `Long` stays `Long`, `String` → `String?`, `ByteArray` → `ByteArray?`
- Remove `import io.zenoh.exceptions.ZError`

For each public adapter method wrapping an external fun:
- Add `error: Array<String?>` as last parameter, pass through
- Return the raw sentinel value without throwing

**Files to update in zenoh-jni-runtime:**
- `commonMain/kotlin/io/zenoh/jni/JNISession.kt`
- `commonMain/kotlin/io/zenoh/jni/JNIConfig.kt`
- `commonMain/kotlin/io/zenoh/jni/JNIKeyExpr.kt`
- `commonMain/kotlin/io/zenoh/jni/JNIPublisher.kt`
- `commonMain/kotlin/io/zenoh/jni/JNIQuery.kt`
- `commonMain/kotlin/io/zenoh/jni/JNIQuerier.kt`
- `commonMain/kotlin/io/zenoh/jni/JNIScout.kt`
- `commonMain/kotlin/io/zenoh/jni/JNILogger.kt`
- `commonMain/kotlin/io/zenoh/jni/JNIAdvancedPublisher.kt`
- `commonMain/kotlin/io/zenoh/jni/JNIAdvancedSubscriber.kt`
- `commonMain/kotlin/io/zenoh/jni/JNIZenohId.kt`
- `jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytes.kt`
- `jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.kt`

---

## Phase 5 — Kotlin `zenoh-java`

### 5a. Create ZError.kt
Create `zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`:
```kotlin
package io.zenoh.exceptions
class ZError(override val message: String? = null) : Exception()
```

### 5b. Update all JNI call sites

Pattern for Long/pointer-returning (error indicator = 0L):
```kotlin
val error = arrayOfNulls<String>(1)
val ptr = jniXxx.someMethod(params, error)
if (ptr == 0L) throw ZError(error[0] ?: "Unknown error in X")
```

Pattern for Int-returning (error indicator < 0):
```kotlin
val error = arrayOfNulls<String>(1)
val result = jniXxx.someMethod(params, error)
if (result < 0) throw ZError(error[0] ?: "Unknown error in X")
```

Pattern for Boolean-turned-Int:
```kotlin
val error = arrayOfNulls<String>(1)
val result = JNIKeyExpr.intersects(a, b, error)
if (result < 0) throw ZError(error[0] ?: "Unknown error")
val intersects = result != 0
```

Pattern for nullable String/ByteArray/object:
```kotlin
val error = arrayOfNulls<String>(1)
val result = jniXxx.getString(params, error)
if (result == null) throw ZError(error[0] ?: "Unknown error")
```

**Files to update in zenoh-java:**
- `commonMain/kotlin/io/zenoh/Session.kt` (~16 call sites)
- `commonMain/kotlin/io/zenoh/Zenoh.kt` — open session and scout call sites
- `commonMain/kotlin/io/zenoh/Config.kt` — config loading
- `commonMain/kotlin/io/zenoh/keyexpr/KeyExpr.kt` — tryFrom, autocanonize, intersects, includes, relationTo, join, concat
- `commonMain/kotlin/io/zenoh/pubsub/Publisher.kt` — put, delete
- `commonMain/kotlin/io/zenoh/query/Query.kt` — replySuccess, replyError, replyDelete
- `commonMain/kotlin/io/zenoh/query/Querier.kt` — get
- `commonMain/kotlin/io/zenoh/config/ZenohId.kt` — toString
- `commonMain/kotlin/io/zenoh/Logger.kt` — startLogs
- `jvmAndAndroidMain/kotlin/io/zenoh/ext/ZDeserializer.kt` — JNIZBytes.deserialize call
- `jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerializer.kt` — JNIZBytes.serialize call
- Any advanced publisher/subscriber files calling JNI methods

### 5c. Keep `@Throws(ZError::class)` annotations on public API methods
Public API methods in `zenoh-java` still throw `ZError` — just from Kotlin code now.

---

## Verification

1. **Rust completeness:** `grep -rn "throw_exception!" zenoh-jni/src/` must return 0 results (or only the macro definition — never called from exported functions).

2. **Rust resolves no ZError class:** `KOTLIN_EXCEPTION_NAME` and `throw_on_jvm()` removed from `errors.rs`. No Rust code path resolves `io/zenoh/exceptions/ZError`.

3. **Runtime exports no ZError:** `grep -rn "ZError" zenoh-jni-runtime/src/` must return 0 results after deletion.

4. **No @Throws in runtime:** `grep -rn "@Throws" zenoh-jni-runtime/src/` must return 0 results.

5. **API layer builds:** `zenoh-java` compiles; `ZError` exists only in `zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`.

6. **Tests pass:** Run existing test suite — behavior unchanged from consumer perspective (ZError still surfaces at zenoh-java API level, thrown from Kotlin).

---

## Key files summary

| File | Action |
|---|---|
| `zenoh-jni/src/errors.rs` | Add `set_error_string`, remove `throw_on_jvm` + `KOTLIN_EXCEPTION_NAME` |
| `zenoh-jni/src/utils.rs` | Replace throw_exception! in load_on_close with tracing::error! |
| `zenoh-jni/src/session.rs` | 16 exported fns — largest single file |
| `zenoh-jni/src/key_expr.rs` | 7 throw_exception! calls |
| `zenoh-jni/src/ext/advanced_publisher.rs` | 5 calls |
| `zenoh-jni/src/ext/advanced_subscriber.rs` | 4 calls |
| `zenoh-jni/src/zbytes.rs` | 2 calls (was incorrectly excluded before) |
| `zenoh-jni/src/zbytes_kotlin.rs` | 2 calls (was incorrectly excluded before) |
| `zenoh-jni-runtime/.../exceptions/ZError.kt` | DELETE |
| `zenoh-jni-runtime/.../jni/JNIZenohId.kt` | Update (missing from prior plan) |
| `zenoh-jni-runtime/.../jni/JNIZBytes.kt` | Update (missing from prior plan) |
| `zenoh-jni-runtime/.../jni/JNIZBytesKotlin.kt` | Update (missing from prior plan) |
| `zenoh-java/.../exceptions/ZError.kt` | CREATE |
| `zenoh-java/.../Zenoh.kt` | Update scout/open call sites (missing from prior plan) |
| `zenoh-java/.../config/ZenohId.kt` | Update toString call site (missing from prior plan) |
| `zenoh-java/.../ext/ZDeserializer.kt` | Update JNIZBytes.deserialize call |
| `zenoh-java/.../ext/ZSerializer.kt` | Update JNIZBytes.serialize call |

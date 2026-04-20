# Plan: Throw Exceptions from Java (zenoh-java JNI Error Handling Refactor)

## Context

**Problem:** `zenoh-jni-runtime` throws JVM exceptions from Rust via `throw_exception!` → `ZError::throw_on_jvm()`. The `zenoh-kotlin` library (separate repo) reuses `zenoh-jni-runtime` directly and wraps every JNI call in `runCatching` to handle those exceptions, which is inconvenient.

**Goal:**
- Rust JNI functions never throw JVM exceptions. Instead they accept an `error_out: JObjectArray` out-parameter (last parameter), return a sentinel value on failure, and write the error message into `error_out[0]`.
- `ZError.kt` is removed from `zenoh-jni-runtime` and moved to `zenoh-java`.
- Exception throwing (`throw ZError(...)`) lives only at the `zenoh-java` API layer.

**Analog:** The refactor is mechanical and uniform — no new design is being introduced, just a boundary shift from Rust→JVM exception raising to Kotlin error-sentinel inspection at the `zenoh-java` layer.

**Current branch state:** Work branch `zbobr_fix-75-throw-execptions-from-java` has no changes yet relative to `origin/common-jni`. All changes start from scratch.

---

## Error-indicator conventions (new JNI API)

| Rust original return | New Kotlin/Rust return | Error indicator | Success |
|---|---|---|---|
| `jlong` (pointer/handle) | `Long` | `0L` | raw pointer cast to Long |
| `jobject` / `jbyteArray` | `ByteArray?` / `Any?` | `null` | valid object |
| `jstring` | `String?` | `null` | valid string |
| `jint` (formerly `Unit`) | `Int` | `-1` | `0` |
| `jint` (formerly `Boolean`) | `Int` | `-1` | `0` (false) or `1` (true) |
| `jint` (enum) | `Int` | negative | non-negative ordinal |

`error_out: JObjectArray` is **always the last parameter** of each modified JNI exported function. On success it is not modified.

---

## Phase 1 — Rust `zenoh-jni/src/errors.rs`

- Add helper `pub(crate) fn set_error_string(env: &mut JNIEnv, error_out: &JObjectArray, msg: &str)` that writes `msg` into `error_out[0]` via JNI `set_object_array_element`. Handle JNI failures by logging with `tracing::error!` and swallowing.
- Remove `throw_on_jvm()` method and `KOTLIN_EXCEPTION_NAME` constant from `ZError`. Rust never throws JVM exceptions after this change.
- Retain `ZError` struct, `zerror!` macro, `ZResult<T>` — still used for internal Rust error propagation.
- The `throw_exception!` macro may be removed or kept unused.

---

## Phase 2 — Rust `zenoh-jni/src/utils.rs` (async callback path)

The `load_on_close` function (approx lines 163–189) attaches a daemon thread and calls a Java `run()` callback. It currently calls `throw_exception!(env, zerror!(...))` on failure. Since this is async with no caller-owned out-parameter, replace `throw_exception!(env, ...)` with `tracing::error!("Error while running 'onClose' callback: {}", err)` and return early. Do not throw any JVM exception from Rust in this path.

---

## Phase 3 — Rust JNI exported functions (all files)

Apply to all `throw_exception!` call sites in exported functions across 14+ files. For each:
1. Add `error_out: JObjectArray` as the last parameter
2. Change return type as per convention table above
3. Replace `throw_exception!(env, err); <sentinel>` with `set_error_string(&mut env, &error_out, &err.to_string()); <sentinel>`

### Exclude (free/close/undeclare — always succeed, never throw)
All `free*ViaJNI`, `close*ViaJNI`, `undeclare*ViaJNI` functions. Also `undeclareKeyExprViaJNI` in `session.rs`.

### Files and functions to migrate

**`session.rs`** (~19 exported functions):
- `openSessionViaJNI` → Long, error=0
- `openSessionWithJsonConfigViaJNI` → Long, error=0 (migrate for Rust correctness even if no Kotlin wrapper)
- `openSessionWithYamlConfigViaJNI` → Long, error=0 (same)
- `declarePublisherViaJNI` → Long, error=0
- `putViaJNI` (session) → Int, error=-1
- `deleteViaJNI` (session) → Int, error=-1
- `declareSubscriberViaJNI` → Long, error=0
- `declareQuerierViaJNI` → Long, error=0
- `declareQueryableViaJNI` → Long, error=0
- `declareKeyExprViaJNI` → Long, error=0
- `getViaJNI` → Int, error=-1
- `getPeersZidViaJNI` → jobject (nullable List), error=null
- `getRoutersZidViaJNI` → jobject (nullable List), error=null
- `getZidViaJNI` → jbyteArray (nullable), error=null
- `declareLivelinessTokenViaJNI` → Long, error=0
- `declareLivelinessSubscriberViaJNI` → Long, error=0
- `livelinessGetViaJNI` → Int, error=-1
- `declareAdvancedSubscriberViaJNI` → Long, error=0
- `declareAdvancedPublisherViaJNI` → Long, error=0

**`config.rs`** (6 functions):
- `loadDefaultConfigViaJNI` → Long (add error_out for API uniformity, never fails in practice)
- `loadConfigFileViaJNI` → Long, error=0
- `loadJsonConfigViaJNI` → Long, error=0
- `loadYamlConfigViaJNI` → Long, error=0
- `getJsonViaJNI` → jstring (nullable), error=null
- `getIdViaJNI` → jbyteArray (nullable), error=null
- `insertJson5ViaJNI` → Int, error=-1

**`key_expr.rs`** (7 calls):
- `tryFromViaJNI`, `autocanonizeViaJNI`, `joinViaJNI`, `concatViaJNI` → jstring (nullable), error=null
- `intersectsViaJNI`, `includesViaJNI` → Int, error=-1 (formerly jboolean)
- `relationToViaJNI` → Int, error=-1

**`publisher.rs`** (2 calls):
- `putViaJNI`, `deleteViaJNI` → Int, error=-1

**`query.rs`** (3 calls):
- `replySuccessViaJNI`, `replyErrorViaJNI`, `replyDeleteViaJNI` → Int, error=-1

**`querier.rs`** (1 call):
- `getViaJNI` → Int, error=-1

**`scouting.rs`** (1 call):
- `scoutViaJNI` → Long, error=0

**`logger.rs`** (1 call):
- `startLogsViaJNI` → Int, error=-1

**`zenoh_id.rs`** (1 call):
- `toStringViaJNI` → jstring (nullable), error=null

**`ext/advanced_publisher.rs`** (5 calls):
- `putViaJNI`, `deleteViaJNI` → Int, error=-1
- `declareMatchingListenerViaJNI` → Long, error=0
- `declareBackgroundMatchingListenerViaJNI` → Int, error=-1
- `getMatchingStatusViaJNI` → Int, error=-1 (formerly jboolean)

**`ext/advanced_subscriber.rs`** (4 calls):
- `declareDetectPublishersSubscriberViaJNI`, `declareSampleMissListenerViaJNI` → Long, error=0
- `declareBackgroundDetectPublishersSubscriberViaJNI`, `declareBackgroundSampleMissListenerViaJNI` → Int, error=-1

**`zbytes.rs`** (2 calls — previously incorrectly excluded):
- `serializeViaJNI` → jbyteArray (nullable), error=null
- `deserializeViaJNI` → jobject (nullable Any), error=null

**`zbytes_kotlin.rs`** (2 calls — previously incorrectly excluded):
- `serializeViaJNI` → jbyteArray (nullable), error=null
- `deserializeViaJNI` → jobject (nullable Any), error=null

---

## Phase 4 — Kotlin `zenoh-jni-runtime`

### 4a. Delete ZError.kt
Remove `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`.

### 4b. Update all JNI adapter files

For every `external fun` whose Rust counterpart changed:
- Remove `@Throws(ZError::class)` annotation
- Add `error: Array<String?>` as the last parameter
- Change return type: `Unit` → `Int`, `Boolean` → `Int`, `String` → `String?`, `ByteArray` → `ByteArray?`, `Long` stays `Long`
- For object-returning wrappers: **all adapter methods that construct a Kotlin JNI wrapper object from a Long pointer must return the wrapper as nullable and return `null` when the pointer is 0L**, rather than constructing a wrapper with an invalid pointer. This applies to: `JNIPublisher?`, `JNISubscriber?`, `JNIQueryable?`, `JNIQuerier?`, `JNIKeyExpr?`, `JNIConfig?`, `JNIAdvancedPublisher?`, `JNIAdvancedSubscriber?`, `JNIMatchingListener?`, `JNISampleMissListener?`, `JNILivelinessToken?`, `JNIScout?` — any wrapper returned by a previously-throwing function. Similarly, adapters returning `List<ByteArray>?` or `Any?` (zbytes deserialize) become nullable.
- Remove `import io.zenoh.exceptions.ZError` from each file.
- For public adapter methods wrapping `external fun`: add `error: Array<String?>` as last parameter, pass through, return the raw sentinel/nullable value without throwing.
- **Do not throw in runtime adapters.**

**Files to update in zenoh-jni-runtime:**
- `commonMain/kotlin/io/zenoh/jni/JNISession.kt` — largest file; includes liveliness methods
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
(Same content and package as the deleted runtime version — all existing imports in zenoh-java source remain valid.)

### 5b. Update all JNI call sites

**Pattern for Long/pointer-returning (error indicator = 0L):**
```kotlin
val error = arrayOfNulls<String>(1)
val ptr = jniXxx.someMethod(params, error)
if (ptr == 0L) throw ZError(error[0] ?: "Unknown error in X")
```
Or if the adapter returns a nullable wrapper:
```kotlin
val error = arrayOfNulls<String>(1)
val jniFoo = jniXxx.someMethod(params, error) ?: throw ZError(error[0] ?: "Unknown error")
```

**Pattern for Int-returning (error indicator < 0):**
```kotlin
val error = arrayOfNulls<String>(1)
val result = jniXxx.someMethod(params, error)
if (result < 0) throw ZError(error[0] ?: "Unknown error in X")
```

**Pattern for Boolean-turned-Int:**
```kotlin
val error = arrayOfNulls<String>(1)
val result = JNIKeyExpr.intersects(a, b, error)
if (result < 0) throw ZError(error[0] ?: "Unknown error")
val intersects = result != 0
```

**Pattern for nullable String/ByteArray/object:**
```kotlin
val error = arrayOfNulls<String>(1)
val result = jniXxx.getString(params, error)
    ?: throw ZError(error[0] ?: "Unknown error")
```

### 5c. Files to update in zenoh-java — complete list

- `commonMain/kotlin/io/zenoh/Session.kt` — ~16 JNI call sites (session open, declare publisher/subscriber/querier/queryable/keyexpr/advancedPublisher/advancedSubscriber, put/delete/get, getPeers/getRouters/getZid)
- **`commonMain/kotlin/io/zenoh/liveliness/Liveliness.kt`** — calls `jniSession.declareLivelinessToken()`, `jniSession.livelinessGet()`, `jniSession.declareLivelinessSubscriber()` **directly** (not through Session.kt). Six call sites across three overloaded method groups (`declareToken`, three `get` overloads, three `declareSubscriber` overloads).
- `commonMain/kotlin/io/zenoh/Zenoh.kt` — `JNIScout.scout()` call site (~lines 54–106) and session open calls
- `commonMain/kotlin/io/zenoh/Config.kt` — config loading call sites
- `commonMain/kotlin/io/zenoh/keyexpr/KeyExpr.kt` — tryFrom, autocanonize, intersects, includes, relationTo, join, concat
- `commonMain/kotlin/io/zenoh/pubsub/Publisher.kt` — put, delete
- `commonMain/kotlin/io/zenoh/query/Query.kt` — replySuccess, replyError, replyDelete
- `commonMain/kotlin/io/zenoh/query/Querier.kt` — get
- `commonMain/kotlin/io/zenoh/config/ZenohId.kt` — toString calls `JNIZenohId.toString()`
- `commonMain/kotlin/io/zenoh/Logger.kt` — startLogs
- `jvmAndAndroidMain/kotlin/io/zenoh/ext/ZDeserializer.kt` — `JNIZBytes.deserialize()` call site
- `jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerializer.kt` — `JNIZBytes.serialize()` call site
- Advanced publisher/subscriber files if they directly call JNI adapter methods

### 5d. Keep `@Throws(ZError::class)` on public API methods
Public API methods in `zenoh-java` still throw `ZError` — but now thrown from Kotlin code, not propagated from JNI.

---

## Verification

1. **No Rust exception throwing:**
   `grep -rn "throw_exception!" zenoh-jni/src/` must return 0 results (or only the macro definition with no call sites in any exported function).

2. **Rust no longer references ZError class:**
   `grep -rn "KOTLIN_EXCEPTION_NAME\|throw_on_jvm" zenoh-jni/src/` must return 0 results.

3. **Runtime exports no ZError:**
   `grep -rn "ZError" zenoh-jni-runtime/src/` must return 0 results.

4. **No @Throws in runtime:**
   `grep -rn "@Throws" zenoh-jni-runtime/src/` must return 0 results.

5. **ZError exists only in zenoh-java:**
   `find . -name "ZError.kt"` must return exactly one result: `zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`.

6. **No unhandled JNI call sites in zenoh-java Liveliness:**
   Verify `Liveliness.kt` uses the error-array pattern for all `declareLivelinessToken`, `livelinessGet`, and `declareLivelinessSubscriber` calls.

7. **Build:** `./gradlew build` must succeed for both `zenoh-jni-runtime` and `zenoh-java`.

8. **Tests:** Run existing test suite — behavior is unchanged from consumer perspective (ZError exceptions still surface at the zenoh-java API level, thrown from Kotlin).

---

## Key files summary

| File | Action |
|---|---|
| `zenoh-jni/src/errors.rs` | Add `set_error_string`, remove `throw_on_jvm` + `KOTLIN_EXCEPTION_NAME` |
| `zenoh-jni/src/utils.rs` | Replace `throw_exception!` in `load_on_close` with `tracing::error!` |
| `zenoh-jni/src/session.rs` | ~19 exported functions — largest single Rust file to change |
| `zenoh-jni/src/config.rs` | 6 functions |
| `zenoh-jni/src/key_expr.rs` | 7 functions |
| `zenoh-jni/src/zbytes.rs` | 2 functions (was incorrectly excluded before) |
| `zenoh-jni/src/zbytes_kotlin.rs` | 2 functions (was incorrectly excluded before) |
| `zenoh-jni/src/ext/advanced_publisher.rs` | 5 functions |
| `zenoh-jni/src/ext/advanced_subscriber.rs` | 4 functions |
| `zenoh-jni-runtime/.../exceptions/ZError.kt` | **DELETE** |
| `zenoh-jni-runtime/.../jni/JNISession.kt` | Update all session + liveliness methods |
| `zenoh-jni-runtime/.../jni/JNIZenohId.kt` | Update (was missing from prior plan) |
| `zenoh-jni-runtime/.../jni/JNIZBytes.kt` | Update (was missing from prior plan) |
| `zenoh-jni-runtime/.../jni/JNIZBytesKotlin.kt` | Update (was missing from prior plan) |
| `zenoh-java/.../exceptions/ZError.kt` | **CREATE** |
| `zenoh-java/.../liveliness/Liveliness.kt` | **Update liveliness call sites (was missing from prior plan)** |
| `zenoh-java/.../Zenoh.kt` | Update scout/open call sites (was missing from prior plan) |
| `zenoh-java/.../config/ZenohId.kt` | Update toString call site (was missing from prior plan) |
| `zenoh-java/.../ext/ZDeserializer.kt` | Update JNIZBytes.deserialize call |
| `zenoh-java/.../ext/ZSerializer.kt` | Update JNIZBytes.serialize call |
| `zenoh-java/.../Session.kt` | ~16 JNI call sites |

# Plan: Throw Exceptions from Java (zenoh-java JNI Error Handling Refactor)

## Context

**Problem:** `zenoh-jni-runtime` throws JVM exceptions from Rust via `throw_exception!` → `ZError::throw_on_jvm()`. The `zenoh-kotlin` library (separate repo) reuses `zenoh-jni-runtime` directly and must wrap every JNI call in `runCatching`, which is inconvenient.

**Goal:** Eliminate exception throwing from the Rust/JNI boundary. JNI functions instead use an out-parameter `error: Array<String?>` to pass back error messages and encode failure in their return values. Exception throwing (`throw ZError(...)`) is pushed up to the `zenoh-java` layer. `ZError.kt` moves from `zenoh-jni-runtime` to `zenoh-java`.

**Approach:** Mechanical refactor across three layers (Rust → Kotlin runtime → Kotlin API). The pattern is uniform and consistent. No behavior change visible to `zenoh-java` consumers.

---

## Error-indicator conventions (new API)

| Original Rust return type | New return type | Error indicator | Success |
|---|---|---|---|
| `*const T` (pointer as jlong) | `jlong` | `0` | raw pointer cast to jlong |
| `jstring` | `jstring` | `JString::default().as_raw()` (null) | valid jstring |
| `jboolean` | `jint` | `-1` | `0` (false) or `1` (true) |
| `jint` (enum) | `jint` | `-1` (or any negative) | non-negative enum ordinal |
| `void` (formerly unit) | `jint` | `-1` | `0` |
| `jobject`/`jbyteArray` | same | `JObject::null()` cast | valid object |

The `error: Array<String?>` out-parameter is always the **last** parameter of each modified JNI function. On success it is not modified.

---

## Phase 1 — Rust `zenoh-jni/src/errors.rs`

- Add `pub(crate) fn set_error_string(env: &mut JNIEnv, error_out: &JObjectArray, msg: &str)` that writes `msg` into `error_out[0]`. Handle JNI failures by logging with `tracing::error!` and swallowing.
- Remove `throw_on_jvm()` method and `KOTLIN_EXCEPTION_NAME` constant from `ZError` (no longer needed — Rust never throws JVM exceptions).
- Remove (or leave unused) `throw_exception!` macro — it will no longer be called in exported functions.
- Retain `ZError` struct, `zerror!` macro, `ZResult<T>` — still used for internal Rust error propagation.
- Add `use jni::objects::JObjectArray;` import.

---

## Phase 2 — Rust JNI exported functions

### Functions to EXCLUDE (cleanup/free, always succeed — do not modify)

- `freePtrViaJNI` variants for Publisher, Subscriber, Queryable, Query, Querier, Scout, KeyExpr, Config, AdvancedPublisher, AdvancedSubscriber, MatchingListener, SampleMissListener
- `closeSessionViaJNI` in session.rs
- `undeclareViaJNI` for LivelinessToken in liveliness.rs

### Functions to CHANGE — add `error_out: JObjectArray` as last param, update return type and error path

Apply to all exported functions NOT in the exclude list. Replace every:
```rust
throw_exception!(env, err);
<error_return_value>
```
with:
```rust
set_error_string(&mut env, &error_out, &err.to_string());
<error_return_value>
```

**`session.rs`** (~15 functions):
- `openSessionViaJNI`: `*const Session` → `jlong`, error = 0
- `declarePublisherViaJNI`, `declareSubscriberViaJNI`, `declareQuerierViaJNI`, `declareQueryableViaJNI`, `declareKeyExprViaJNI`, `declareLivelinessTokenViaJNI`, `declareLivelinessSubscriberViaJNI`, `declareAdvancedSubscriberViaJNI`, `declareAdvancedPublisherViaJNI`: all `*const T` → `jlong`, error = 0
- `putViaJNI`, `deleteViaJNI`, `undeclareKeyExprViaJNI`, `getViaJNI`, `livelinessGetViaJNI`: `void` → `jint`, error = -1
- `getZidViaJNI`: `jbyteArray` → `jbyteArray`, error = null
- `getPeersZidViaJNI`, `getRoutersZidViaJNI`: `jobject` (list) → `jobject`, error = null

**`publisher.rs`**: `putViaJNI`, `deleteViaJNI`: `void` → `jint`

**`key_expr.rs`**:
- `tryFromViaJNI`, `autocanonizeViaJNI`, `joinViaJNI`, `concatViaJNI`: `jstring` → `jstring`, error = null
- `intersectsViaJNI`, `includesViaJNI`: `jboolean` → `jint`, error = -1
- `relationToViaJNI`: stays `jint`, add `error_out` param, error = -1

**`config.rs`**:
- `loadDefaultConfigViaJNI`: `*const Config` → `jlong` (add `error_out` for API uniformity; never fails)
- `loadConfigFileViaJNI`, `loadJsonConfigViaJNI`, `loadYamlConfigViaJNI`: `*const Config` → `jlong`
- `getJsonViaJNI`: `jstring`, error = null
- `insertJson5ViaJNI`: `void` → `jint`
- `getIdViaJNI`: `jbyteArray`, error = null

**`query.rs`**: `replySuccessViaJNI`, `replyErrorViaJNI`, `replyDeleteViaJNI`: `void` → `jint`

**`querier.rs`**: `getViaJNI`: `void` → `jint`

**`scouting.rs`**: `scoutViaJNI`: `*const Scout<()>` → `jlong`

**`logger.rs`**: `startLogsViaJNI`: `void` → `jint`

**`zenoh_id.rs`**: `toStringViaJNI`: `jstring`, error = null

**`ext/advanced_publisher.rs`**:
- `putViaJNI`, `deleteViaJNI`: `void` → `jint`
- `declareMatchingListenerViaJNI`: `*const MatchingListener<()>` → `jlong`
- `declareBackgroundMatchingListenerViaJNI`: `void` → `jint`
- `getMatchingStatusViaJNI`: `jboolean` → `jint`

**`ext/advanced_subscriber.rs`**:
- `declareDetectPublishersSubscriberViaJNI`, `declareSampleMissListenerViaJNI`: `*const T` → `jlong`
- `declareBackgroundDetectPublishersSubscriberViaJNI`, `declareBackgroundSampleMissListenerViaJNI`: `void` → `jint`

**`zbytes.rs` / `zbytes_kotlin.rs`**: Out of scope — do not modify.

---

## Phase 3 — Kotlin `zenoh-jni-runtime`

### 3a. Delete `ZError.kt`
Remove `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`.

### 3b. Update each JNI adapter file

For every `external fun` whose Rust counterpart changed:
- Remove `@Throws(ZError::class)` annotation
- Add `error: Array<String?>` as last parameter
- Change return type to match: `Unit` → `Int`, `Boolean` → `Int`, `Long` stays `Long`, `String` → `String?`, etc.
- Remove `import io.zenoh.exceptions.ZError` from the file

For each public adapter method wrapping an external fun:
- Add `error: Array<String?>` as last parameter
- Pass `error` through to the external fun call
- Return the raw indicator value (do not throw)
- Remove `@Throws(ZError::class)` annotation

**Do not change** `freePtrViaJNI`/close/free/undeclare adapter methods — they are in the exclude list.

### 3c. Specific adapter method return type changes

- Methods wrapping formerly-void externals: return `Int` (0 or -1)
- Methods wrapping formerly-Boolean externals (`intersects`, `includes`, `getMatchingStatus`): return `Int` (-1, 0, or 1)
- Methods wrapping pointer-returning externals that previously returned `JNIFoo(ptr)`: return `JNIFoo?` (null when ptr == 0L) so the adapter layer remains useful.

Example for JNIPublisher:
```kotlin
// Before
@Throws(ZError::class)
fun put(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?) {
    putViaJNI(ptr, payload, encodingId, encodingSchema, attachment)
}

// After
fun put(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?, error: Array<String?>): Int =
    putViaJNI(ptr, payload, encodingId, encodingSchema, attachment, error)
```

---

## Phase 4 — Kotlin `zenoh-java`

### 4a. Add ZError
Create `zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`:
```kotlin
package io.zenoh.exceptions
class ZError(override val message: String? = null): Exception()
```
(Same content, same package — all existing imports in `zenoh-java` files resolve unchanged.)

### 4b. Update every call site

For each call into a JNI runtime method, apply this pattern:

**For Long/pointer-returning (error indicator = 0L):**
```kotlin
val error = arrayOfNulls<String>(1)
val ptr = jniXxx.someMethod(params, error)
if (ptr == 0L) throw ZError(error[0] ?: "Unknown error opening X")
```

**For Int-returning (error indicator < 0):**
```kotlin
val error = arrayOfNulls<String>(1)
val result = jniXxx.someMethod(params, error)
if (result < 0) throw ZError(error[0] ?: "Unknown error in X")
```

**For Boolean-turned-Int (intersects, includes, getMatchingStatus):**
```kotlin
val error = arrayOfNulls<String>(1)
val result = JNIKeyExpr.intersects(a, aStr, b, bStr, error)
if (result < 0) throw ZError(error[0] ?: "Unknown error")
val intersects = result != 0
```

**For nullable String/ByteArray/object:**
```kotlin
val error = arrayOfNulls<String>(1)
val result = jniXxx.getString(params, error)
if (result == null) throw ZError(error[0] ?: "Unknown error")
```

### 4c. Keep `@Throws(ZError::class)` annotations

Public API methods in `zenoh-java` (Session, Publisher, etc.) keep their `@Throws(ZError::class)` annotations — they still throw ZError, just from Kotlin code rather than propagated from JNI.

### 4d. Files to update in zenoh-java

- `Session.kt` — most JNI calls are here; ~20 call sites
- `Config.kt` — config loading
- `keyexpr/KeyExpr.kt` — tryFrom, autocanonize, intersects, includes, relationTo, join, concat
- `pubsub/Publisher.kt` — put, delete
- `query/Query.kt` — replySuccess, replyError, replyDelete
- `query/Querier.kt` — get
- `scouting/Scout.kt` — scout declaration
- `liveliness/Liveliness.kt` — liveliness operations
- `Logger.kt` — startLogs
- Any advanced publisher/subscriber usage

---

## Verification

1. **Rust**: `cargo check` in `zenoh-jni/` must pass. Then: `grep -rn "throw_exception!" zenoh-jni/src/` must show 0 occurrences in exported function bodies (only the macro definition itself if kept).

2. **Runtime**: Build `zenoh-jni-runtime`. `grep -rn "ZError" zenoh-jni-runtime/src/` must return 0 results.

3. **API layer**: Build `zenoh-java`. ZError must be found in `zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/`.

4. **Tests**: Run existing test suite — behavior is unchanged from consumer perspective (ZError exceptions still surface, just thrown from Kotlin rather than propagated from JNI).

5. **Sanity grep**: No `@Throws(ZError::class)` on `external fun` declarations in `zenoh-jni-runtime`.

---

## Key file paths

- `zenoh-jni/src/errors.rs` — add `set_error_string`
- `zenoh-jni/src/session.rs` — largest single file to modify (~15 functions)
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt` — DELETE
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt` — largest Kotlin file (~30+ external funs)
- `zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt` — CREATE
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt` — most call sites

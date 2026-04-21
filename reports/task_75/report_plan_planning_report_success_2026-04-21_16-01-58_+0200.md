# Implementation Plan: Uniform JNI Error API (String? return + out parameter)

## Context

The `zenoh-jni-runtime` module provides JNI bindings between Kotlin and the Rust `zenoh-jni` crate. The work branch already converted exception-throwing to an `error: Array<String?>` out-parameter + typed-return-value pattern, but this is an intermediate state. The final requested API is:

- Return type is always `String?`: **null = success**, **non-null = error message**
- Real return value is stored in a typed `out` parameter

Additionally, a batch of Rust `///` doc comment blocks were accidentally removed and must be restored.

---

## Key Architectural Invariants

Three strict layer boundaries must be preserved:

| Layer | Responsibility |
|---|---|
| `zenoh-jni` (Rust) | Returns `jstring` (null = success, non-null = error), writes result to `out` param; never throws JNI exceptions |
| `zenoh-jni-runtime` (Kotlin) | Wraps raw handles into typed JNI* objects; exposes `String?` return; **must NOT throw ZError** |
| `zenoh-java` (Kotlin) | The only layer that converts `String?` errors into `throw ZError(...)` |

`ZError` is defined only in `zenoh-java` (`io.zenoh.exceptions.ZError`). `zenoh-jni-runtime` must not import or use it.

---

## Part 1 — Restore Removed Rust Doc Comment Blocks

**Why removed:** The previous plan iteration stripped `///` documentation comments from JNI export functions in Rust source files when refactoring error-handling.

**What to restore:** All `///` comment blocks on JNI export functions and their private helpers across all Rust source files.

**How to update language:** Where docs previously said "an exception is thrown on the JVM", replace with "the error is returned as a non-null string and the out parameter is left unchanged".

**Files to update (use `git diff origin/common-jni...HEAD` to find exact removed blocks):**
- `zenoh-jni/src/session.rs`
- `zenoh-jni/src/config.rs`
- `zenoh-jni/src/key_expr.rs`
- `zenoh-jni/src/publisher.rs`
- `zenoh-jni/src/querier.rs`
- `zenoh-jni/src/query.rs`
- `zenoh-jni/src/scouting.rs`
- `zenoh-jni/src/logger.rs`
- `zenoh-jni/src/liveliness.rs`
- `zenoh-jni/src/zbytes.rs`
- `zenoh-jni/src/zbytes_kotlin.rs`
- `zenoh-jni/src/zenoh_id.rs`
- `zenoh-jni/src/ext/advanced_publisher.rs`
- `zenoh-jni/src/ext/advanced_subscriber.rs`

---

## Part 2 — New Uniform JNI API Contract

### 2a. Rust Layer (`zenoh-jni`)

**All JNI export functions must return `jstring`**: null = success, non-null = error message string.

**Add to `zenoh-jni/src/errors.rs`:**
```rust
pub(crate) fn make_error_jstring(env: &mut JNIEnv, msg: &str) -> jstring {
    match env.new_string(msg) {
        Ok(s) => s.into_raw(),
        // If new_string() fails with OOM, a Java OutOfMemoryError is already
        // pending in the JVM and will propagate to the caller. Returning null
        // here is safe because the pending exception takes priority. The
        // caller will never interpret null as "success" in this state.
        Err(_) => std::ptr::null_mut(),
    }
}
```

Remove the `set_error_string` function (no longer needed).

**Out parameter type by return category:**

| Return value type | Rust `out` parameter | Rust write call |
|---|---|---|
| Pointer/handle (session, config, publisher, etc.) | `JLongArray` | `env.set_long_array_region(&out, 0, &[ptr as jlong])` |
| `ByteArray` | `JObjectArray` | `env.set_object_array_element(&out, 0, byte_array)` |
| `String` (key expr string, json, id string, etc.) | `JObjectArray` | `env.set_object_array_element(&out, 0, jstring)` |
| `Any` / `jobject` | `JObjectArray` | `env.set_object_array_element(&out, 0, obj)` |
| `List<ByteArray>` | `JObjectArray` | `env.set_object_array_element(&out, 0, list_obj)` |
| **Boolean** (intersects, includes, getMatchingStatus) | **`JIntArray`** | `env.set_int_array_region(&out, 0, &[value as jint])` where value = 1 (true) or 0 (false) |
| **Enum ordinal** (relationTo: SetIntersectionLevel) | **`JIntArray`** | `env.set_int_array_region(&out, 0, &[ordinal as jint])` |
| void / fire-and-forget (put, delete, reply*, get, startLogs, background*) | *(none)* | return `jstring` only |

**Note on existing Int-returning functions with old -1=error pattern:**
Functions like `intersectsViaJNI`, `includesViaJNI`, `relationToViaJNI`, `getMatchingStatusViaJNI` currently return `jint` with -1 on error. These must be converted to return `jstring` and write the result into a `JIntArray out` parameter.

### 2b. `zenoh-jni-runtime` Private External Functions

Private `external fun` declarations must match the new Rust ABI exactly:

| Category | Previous private external signature | New private external signature |
|---|---|---|
| Pointer-returning | `fun openViaJNI(..., error: Array<String?>): Long` | `fun openViaJNI(..., out: LongArray): String?` |
| ByteArray-returning | `fun getZidViaJNI(..., error: Array<String?>): ByteArray?` | `fun getZidViaJNI(..., out: Array<ByteArray?>): String?` |
| String-returning | `fun getJsonViaJNI(..., error: Array<String?>): String?` | `fun getJsonViaJNI(..., out: Array<String?>): String?` |
| Any-returning | `fun deserializeViaJNI(..., error: Array<String?>): Any?` | `fun deserializeViaJNI(..., out: Array<Any?>): String?` |
| List<ByteArray>-returning | `fun getPeersZidViaJNI(..., error: Array<String?>): List<ByteArray>?` | `fun getPeersZidViaJNI(..., out: Array<List<ByteArray>?>): String?` |
| **Boolean-returning** (intersects, includes, getMatchingStatus) | `fun intersectsViaJNI(..., error: Array<String?>): Int` | `fun intersectsViaJNI(..., out: IntArray): String?` |
| **Enum-ordinal-returning** (relationTo) | `fun relationToViaJNI(..., error: Array<String?>): Int` | `fun relationToViaJNI(..., out: IntArray): String?` |
| Void/fire-and-forget | `fun putViaJNI(..., error: Array<String?>): Int` | `fun putViaJNI(...): String?` |

### 2c. `zenoh-jni-runtime` Public Wrapper Functions

**Critical invariant:** The runtime still owns the conversion from raw native handles to typed wrapper objects (`JNISession`, `JNIConfig`, `JNIPublisher`, etc.). The `out` parameter at the public API must use the wrapper type, not `LongArray`.

**Pattern for pointer-returning:**
```kotlin
fun open(config: JNIConfig, out: Array<JNISession?>): String? {
    val rawOut = LongArray(1)
    val err = openSessionViaJNI(config.ptr, rawOut)
    if (err == null) out[0] = JNISession(rawOut[0])
    return err
}
```

**Pattern for Boolean-returning (uses IntArray, callers interpret 1=true/0=false):**
```kotlin
fun intersects(a: JNIKeyExpr?, aStr: String, b: JNIKeyExpr?, bStr: String, out: IntArray): String? =
    intersectsViaJNI(a?.ptr ?: 0, aStr, b?.ptr ?: 0, bStr, out)
```

**Pattern for void/fire-and-forget:**
```kotlin
fun put(...): String? = putViaJNI(...)
```

**Complete public API signature map (all classes, all methods):**

#### `JNIConfig`
| Method | Public out type |
|---|---|
| `loadDefault`, `loadFromFile`, `loadFromJson`, `loadFromYaml` | `Array<JNIConfig?>` |
| `getJson` | `Array<String?>` |
| `insertJson5` | *(no out, returns String?)* |

#### `JNISession`
| Method | Public out type |
|---|---|
| `open` | `Array<JNISession?>` |
| `declarePublisher`, `declareSubscriber`, `declareQueryable`, `declareQuerier`, `declareKeyExpr`, `declareLivelinessToken`, `declareLivelinessSubscriber`, `declareAdvancedPublisher`, `declareAdvancedSubscriber` | `Array<JNI*?>` matching type |
| `getZid` | `Array<ByteArray?>` |
| `getPeersZid`, `getRoutersZid` | `Array<List<ByteArray>?>` |
| `put`, `delete`, `get`, `livelinessGet` | *(no out, returns String?)* |

#### `JNIKeyExpr`
| Method | Public out type |
|---|---|
| `tryFrom` | `Array<String?>` |
| `autocanonize` | `Array<String?>` |
| `intersects` | `IntArray` |
| `includes` | `IntArray` |
| `relationTo` | `IntArray` |
| `join` | `Array<String?>` |
| `concat` | `Array<String?>` |

#### `JNIZenohId`
| Method | Public out type |
|---|---|
| `toString` | `Array<String?>` |

#### `JNILogger`
| Method | Public out type |
|---|---|
| `startLogs` | *(no out, returns String?)* |

#### `JNIQuerier`
| Method | Public out type |
|---|---|
| `get` | *(no out, returns String?)* |

#### `JNIQuery`
| Method | Public out type |
|---|---|
| `replySuccess` | *(no out, returns String?)* |
| `replyError` | *(no out, returns String?)* |
| `replyDelete` | *(no out, returns String?)* |

#### `JNIAdvancedPublisher`
| Method | Public out type |
|---|---|
| `put` | *(no out, returns String?)* |
| `delete` | *(no out, returns String?)* |
| `declareMatchingListener` | `Array<JNIMatchingListener?>` |
| `declareBackgroundMatchingListener` | *(no out, returns String?)* |
| `getMatchingStatus` | `IntArray` |

#### `JNIAdvancedSubscriber`
| Method | Public out type |
|---|---|
| `declareDetectPublishersSubscriber` | `Array<JNISubscriber?>` |
| `declareBackgroundDetectPublishersSubscriber` | *(no out, returns String?)* |
| `declareSampleMissListener` | `Array<JNISampleMissListener?>` |
| `declareBackgroundSampleMissListener` | *(no out, returns String?)* |

#### `JNIScout`
| Method | Public out type |
|---|---|
| `scout` | `Array<JNIScout?>` |

#### `JNIZBytes` / `JNIZBytesKotlin`
| Method | Public out type |
|---|---|
| `serialize` | `Array<ByteArray?>` |
| `deserialize` | `Array<Any?>` |

### 2d. `zenoh-java` Callers

**Pattern for object-returning calls:**
```kotlin
val out = arrayOfNulls<JNISession>(1)
val err = JNISession.open(config, out)
if (err != null) throw ZError(err)
val jniSession = out[0]!!
```

**Pattern for Boolean-from-IntArray calls:**
```kotlin
val out = IntArray(1)
val err = JNIKeyExpr.intersects(jniKeyExpr, keyExpr, other.jniKeyExpr, other.keyExpr, out)
if (err != null) throw ZError(err)
return out[0] == 1
```

**Pattern for enum-ordinal-from-IntArray calls:**
```kotlin
val out = IntArray(1)
val err = JNIKeyExpr.relationTo(jniKeyExpr, keyExpr, other.jniKeyExpr, other.keyExpr, out)
if (err != null) throw ZError(err)
return SetIntersectionLevel.fromInt(out[0])
```

**Pattern for String-from-Array calls (tryFrom, autocanonize, join, concat, toString):**
```kotlin
val out = arrayOfNulls<String>(1)
val err = JNIKeyExpr.tryFrom(keyExpr, out)
if (err != null) throw ZError(err)
return KeyExpr(out[0]!!)
```

**Pattern for void-like calls (put, delete, get, reply*, startLogs, background*):**
```kotlin
val err = jniSession.put(...)
if (err != null) throw ZError(err)
```

**Files to update in `zenoh-java`:**
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Zenoh.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Logger.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/keyexpr/KeyExpr.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/pubsub/Publisher.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/query/Querier.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/query/Query.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/liveliness/Liveliness.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/config/ZenohId.kt`
- `zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerializer.kt`
- `zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZDeserializer.kt`

---

## Execution Order

1. **Update `zenoh-jni/src/errors.rs`** — add `make_error_jstring` helper, remove `set_error_string`.
2. **Update Rust JNI export functions** — one file at a time, changing return type to `jstring`, adding/changing `out` params, restoring doc comments. For scalar (Boolean/enum) functions, change from `jint` return to `jstring` return + `JIntArray` out.
3. **Update `zenoh-jni-runtime` private externals** — match new Rust signatures exactly (LongArray for ptrs, IntArray for scalars, Array<T?> for objects/strings, no out for void-like).
4. **Update `zenoh-jni-runtime` public wrapper functions** — add `LongArray`→wrapper bridging for pointer-returning functions; surface `IntArray` out for scalar-returning functions.
5. **Update `zenoh-java` callers** — allocate typed out arrays, check `String?` return, throw `ZError`.

---

## Verification

1. **Build the project**: `./gradlew build` — must compile without errors.
2. **Run tests**: `./gradlew test` — all existing tests should pass, including `ZBytesInteropTests`.
3. **Confirm no exceptions from runtime**: grep `zenoh-jni-runtime/src` for `throw ZError` and `import io.zenoh.exceptions.ZError` — both should be absent.
4. **Confirm all JNI export functions return `jstring`**: grep `zenoh-jni/src` for `-> \*const`, `-> jint`, `-> jlong` in `ViaJNI` functions — should be gone.
5. **Confirm doc comments restored**: run `git diff origin/common-jni...HEAD -- zenoh-jni/src/` and verify no `///` lines appear as deletions.

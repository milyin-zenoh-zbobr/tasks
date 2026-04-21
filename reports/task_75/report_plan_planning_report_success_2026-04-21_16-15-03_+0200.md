# Implementation Plan: Uniform JNI Error API (String? return + out parameter)

## Context

`zenoh-jni-runtime` provides JNI bindings between Kotlin and the Rust `zenoh-jni` crate. The work branch already partially migrated to an `error: Array<String?>` out-parameter + typed-return-value pattern, but the final requested API is different:

- Return type is **always `String?`**: null = success, non-null = error message  
- Real return value goes through a typed `out` parameter  
- No exception throwing from `zenoh-jni-runtime`  
- `zenoh-java` is the only layer that throws `ZError`

Additionally, `///` doc comment blocks were accidentally removed from Rust JNI export functions and must be restored.

---

## Key Architectural Invariants

| Layer | Responsibility |
|---|---|
| `zenoh-jni` (Rust) | Returns `jstring` (null = success, non-null = error); writes result to `out` param; never throws JNI exceptions |
| `zenoh-jni-runtime` (Kotlin) | Wraps raw handles into typed JNI* objects; exposes `String?` return; **must NOT throw ZError** |
| `zenoh-java` (Kotlin) | The only layer that converts `String?` errors into `throw ZError(...)` |

`ZError` is defined only in `zenoh-java`. `zenoh-jni-runtime` must not import or use it.

---

## Part 1 — Restore Removed Rust Doc Comment Blocks

All `///` comment blocks on JNI export functions and their private helpers must be restored across all Rust source files. Where docs previously said "an exception is thrown on the JVM", replace with "the error is returned as a non-null string and the out parameter is left unchanged".

Files to update (identify exact removed blocks via `git diff origin/common-jni...HEAD`):
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
        // If new_string() fails (OOM), a Java OutOfMemoryError is already
        // pending in the JVM and will propagate to the caller. Returning null
        // here is intentional: the pending JVM exception takes priority and
        // the caller will never interpret null as "success" in this state.
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
| Boolean (intersects, includes, getMatchingStatus) | `JIntArray` | `env.set_int_array_region(&out, 0, &[value as jint])` where value = 1 (true) or 0 (false) |
| Enum ordinal (relationTo: SetIntersectionLevel) | `JIntArray` | `env.set_int_array_region(&out, 0, &[ordinal as jint])` |
| void / fire-and-forget (put, delete, reply*, get, startLogs, background*) | *(none)* | return `jstring` only |

**Legacy session exports to REMOVE:**  
`openSessionWithJsonConfigViaJNI` and `openSessionWithYamlConfigViaJNI` in `zenoh-jni/src/session.rs` are not referenced by any Kotlin file in `zenoh-jni-runtime`. These are dead exports. **Remove them** during migration. This is consistent with the verification step that greps for `-> *const` in `ViaJNI` functions (should find none).

### 2b. `zenoh-jni-runtime` Private External Functions

Private `external fun` declarations must match the new Rust ABI exactly:

| Category | New private external signature |
|---|---|
| Pointer-returning | `fun openViaJNI(..., out: LongArray): String?` |
| ByteArray-returning | `fun getZidViaJNI(..., out: Array<ByteArray?>): String?` |
| String-returning | `fun getJsonViaJNI(..., out: Array<String?>): String?` |
| Any-returning | `fun deserializeViaJNI(..., out: Array<Any?>): String?` |
| List<ByteArray>-returning | `fun getPeersZidViaJNI(..., out: Array<List<ByteArray>?>): String?` |
| Boolean-returning (intersects, includes, getMatchingStatus) | `fun intersectsViaJNI(..., out: IntArray): String?` |
| Enum-ordinal-returning (relationTo) | `fun relationToViaJNI(..., out: IntArray): String?` |
| Void/fire-and-forget | `fun putViaJNI(...): String?` |

### 2c. `zenoh-jni-runtime` Public Wrapper Functions

The runtime owns the conversion from raw native handles to typed wrapper objects. The `out` parameter at the public API uses the wrapper type, not `LongArray`.

**Pattern for pointer-returning:**
```kotlin
fun open(config: JNIConfig, out: Array<JNISession?>): String? {
    val rawOut = LongArray(1)
    val err = openSessionViaJNI(config.ptr, rawOut)
    if (err == null) out[0] = JNISession(rawOut[0])
    return err
}
```

**Pattern for Boolean-returning (callers interpret 1=true/0=false):**
```kotlin
fun intersects(a: JNIKeyExpr?, aStr: String, b: JNIKeyExpr?, bStr: String, out: IntArray): String? =
    intersectsViaJNI(a?.ptr ?: 0, aStr, b?.ptr ?: 0, bStr, out)
```

**Pattern for void/fire-and-forget:**
```kotlin
fun put(...): String? = putViaJNI(...)
```

**Complete public API signature map — all classes, all methods:**

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

#### `JNIPublisher` *(previously missing from plan — now explicit)*
| Method | Public out type |
|---|---|
| `put` | *(no out, returns String?)* |
| `delete` | *(no out, returns String?)* |

Files in the `JNIPublisher` chain:
- `zenoh-jni/src/publisher.rs` — `putViaJNI` and `deleteViaJNI` must change from `jint` return with `error_out: JObjectArray` to `jstring` return with no `out` param (void-like)
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIPublisher.kt` — update private externals and public wrappers
- `zenoh-java/src/commonMain/kotlin/io/zenoh/pubsub/Publisher.kt` — update callers (lines ~84, 93, 112) to check `String?` return and throw `ZError`

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
val err = jniPublisher.put(...)
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
2. **Remove dead session exports** — delete `openSessionWithJsonConfigViaJNI` and `openSessionWithYamlConfigViaJNI` from `zenoh-jni/src/session.rs`.
3. **Update Rust JNI export functions** — one file at a time, changing return type to `jstring`, adding/changing `out` params, restoring doc comments. Scalar (Boolean/enum) functions change from `jint` return to `jstring` return + `JIntArray` out. Publisher `put`/`delete` change from `jint` return with `error_out: JObjectArray` to `jstring` return with no `out` param.
4. **Update `zenoh-jni-runtime` private externals** — match new Rust signatures exactly.
5. **Update `zenoh-jni-runtime` public wrapper functions** — add `LongArray`→wrapper bridging for pointer-returning; surface `IntArray` out for scalar-returning; remove `error: Array<String?>` pattern completely.
6. **Update `zenoh-java` callers** — allocate typed out arrays, check `String?` return, throw `ZError`.

---

## Verification

1. **Build the project**: `./gradlew build` — must compile without errors.
2. **Run tests**: `./gradlew test` — all existing tests pass, including `ZBytesInteropTests`.
3. **Confirm no exceptions from runtime**: grep `zenoh-jni-runtime/src` for `throw ZError` and `import io.zenoh.exceptions.ZError` — both should be absent.
4. **Confirm all JNI export functions return `jstring`**: grep `zenoh-jni/src` for `-> \*const`, `-> jint`, `-> jlong` in `ViaJNI` functions — should be gone.
5. **Confirm no legacy error pattern**: grep `zenoh-jni-runtime/src` for `error: Array<String?>` — should be gone.
6. **Confirm doc comments restored**: run `git diff origin/common-jni...HEAD -- zenoh-jni/src/` and verify no `///` lines appear as deletions.

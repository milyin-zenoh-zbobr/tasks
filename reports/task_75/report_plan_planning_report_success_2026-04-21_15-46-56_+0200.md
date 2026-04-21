# Implementation Plan: Uniform JNI Error API (String? return + out parameter)

## Context

The `zenoh-jni-runtime` module provides JNI bindings between Kotlin and the Rust `zenoh-jni` crate. The previous design had each JNI function throw Java exceptions from Rust on failure, which required downstream consumers (especially `zenoh-kotlin`) to wrap every JNI call in `runCatching`. The work branch already converted exception-throwing to an `error: Array<String?>` out-parameter + typed-return-value pattern, but this is an intermediate state. The final requested API is:

- Return type is always `String?`: **null = success**, **non-null = error message**
- Real return value is stored in a typed `out` parameter

Additionally, a batch of Rust `///` doc comment blocks were accidentally removed and must be restored.

---

## Key Architectural Invariants

Three strict layer boundaries must be preserved:

| Layer | Responsibility |
|---|---|
| `zenoh-jni` (Rust) | Returns `jstring` (null = success), writes result to `out` param; never throws JNI exceptions |
| `zenoh-jni-runtime` (Kotlin) | Wraps raw handles into typed JNI* objects; exposes `String?` return; **must NOT throw ZError** |
| `zenoh-java` (Kotlin) | The only layer that converts `String?` errors into `throw ZError(...)` |

`ZError` is defined only in `zenoh-java` (`io.zenoh.exceptions.ZError`). `zenoh-jni-runtime` must not import or use it.

---

## Part 1 — Restore Removed Rust Doc Comment Blocks

**Why removed:** The previous plan iteration stripped `///` documentation comments from JNI export functions in Rust source files when refactoring error-handling.

**What to restore:** All `///` comment blocks on JNI export functions and their private helpers across all Rust source files.

**How to update language:** Where docs previously said "an exception is thrown on the JVM", replace with "the error is returned as a non-null string and the out parameter is left unchanged / set to zero".

**Files to update:**
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

Use `git diff origin/common-jni...HEAD` to identify exactly which `///` blocks were removed and where they belong.

---

## Part 2 — New Uniform JNI API Contract

### 2a. Rust Layer (`zenoh-jni`)

**Current pattern (to be replaced):**
```rust
pub extern "C" fn ..ViaJNI(.., error_out: JObjectArray) -> *const SomeType {
    match do_work() {
        Ok(val) => Arc::into_raw(val),
        Err(err) => { set_error_string(&mut env, &error_out, &msg); null() }
    }
}
```

**New pattern:**
```rust
pub extern "C" fn ..ViaJNI(.., out: JLongArray) -> jstring {
    match do_work() {
        Ok(val) => {
            let _ = env.set_long_array_region(&out, 0, &[Arc::into_raw(val) as jlong]);
            std::ptr::null_mut()  // null jstring = success
        }
        Err(err) => make_error_jstring(&mut env, &err.to_string())
    }
}
```

**Add to `zenoh-jni/src/errors.rs`:**
```rust
pub(crate) fn make_error_jstring(env: &mut JNIEnv, msg: &str) -> jstring {
    match env.new_string(msg) {
        Ok(s) => s.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}
```

Remove the `set_error_string` function (no longer needed).

**Out parameter type by return category:**

| Return value type | Rust `out` parameter | Rust write call |
|---|---|---|
| Pointer/handle (session, config, etc.) | `JLongArray` | `env.set_long_array_region(&out, 0, &[ptr as jlong])` |
| `ByteArray` | `JObjectArray` | `env.set_object_array_element(&out, 0, byte_array)` |
| `String` | `JObjectArray` | `env.set_object_array_element(&out, 0, jstring)` |
| `Any` / `jobject` | `JObjectArray` | `env.set_object_array_element(&out, 0, obj)` |
| `List<ByteArray>` | `JObjectArray` | `env.set_object_array_element(&out, 0, list_obj)` |
| void / fire-and-forget (put, delete, etc.) | *(none)* | return `jstring` only |

**Note:** The existing `getRoutersZid`/`getPeersZid` already construct a Java List inside Rust; they continue to do so but write the result into the `JObjectArray out` instead of returning it directly.

### 2b. `zenoh-jni-runtime` Private External Functions

Private `external fun` declarations must match the new Rust ABI exactly:

| Category | Previous private external signature | New private external signature |
|---|---|---|
| Pointer-returning | `fun openViaJNI(..., error: Array<String?>): Long` | `fun openViaJNI(..., out: LongArray): String?` |
| ByteArray-returning | `fun getZidViaJNI(..., error: Array<String?>): ByteArray?` | `fun getZidViaJNI(..., out: Array<ByteArray?>): String?` |
| String-returning | `fun getJsonViaJNI(..., error: Array<String?>): String?` | `fun getJsonViaJNI(..., out: Array<String?>): String?` |
| Any-returning | `fun deserializeViaJNI(..., error: Array<String?>): Any?` | `fun deserializeViaJNI(..., out: Array<Any?>): String?` |
| List<ByteArray>-returning | `fun getPeersZidViaJNI(..., error: Array<String?>): List<ByteArray>?` | `fun getPeersZidViaJNI(..., out: Array<List<ByteArray>?>): String?` |
| Void/Int (put, delete, get) | `fun putViaJNI(..., error: Array<String?>): Int` | `fun putViaJNI(...): String?` |

### 2c. `zenoh-jni-runtime` Public Wrapper Functions

**Critical invariant:** The runtime still owns the conversion from raw native handles to typed wrapper objects (`JNISession`, `JNIConfig`, `JNIPublisher`, etc.). The `out` parameter exposed at the public API must use the wrapper type, not `LongArray`.

**Pattern for pointer-returning functions:**
```kotlin
fun open(config: JNIConfig, out: Array<JNISession?>): String? {
    val rawOut = LongArray(1)
    val err = openSessionViaJNI(config.ptr, rawOut)
    if (err == null) out[0] = JNISession(rawOut[0])
    return err
}
```

**Pattern for ByteArray-returning functions (no wrapping needed):**
```kotlin
fun getZid(out: Array<ByteArray?>): String? = getZidViaJNI(sessionPtr, out)
```

**Pattern for void-like functions (put, delete, get):**
```kotlin
fun put(...): String? = putViaJNI(...)
```

**Public API return/out type mapping:**

| Runtime class | Function | Public out type |
|---|---|---|
| `JNIConfig` | `loadDefault`, `loadFromFile`, `loadFromJson`, `loadFromYaml` | `Array<JNIConfig?>` |
| `JNIConfig` | `getJson` | `Array<String?>` |
| `JNIConfig` | `insertJson5` | *(no out, returns String?)* |
| `JNISession` | `open` | `Array<JNISession?>` |
| `JNISession` | `declarePublisher`, `declareSubscriber`, `declareQueryable`, `declareQuerier`, `declareKeyExpr`, `declareLivelinessToken`, `declareLivelinessSubscriber`, `declareAdvancedPublisher`, `declareAdvancedSubscriber` | `Array<JNI*?>` (matching type) |
| `JNISession` | `getZid` | `Array<ByteArray?>` |
| `JNISession` | `getPeersZid`, `getRoutersZid` | `Array<List<ByteArray>?>` |
| `JNISession` | `put`, `delete`, `get`, `livelinessGet` | *(no out, returns String?)* |
| `JNIScout` | `scout` | `Array<JNIScout?>` |
| `JNIAdvancedPublisher` | `declareMatchingListener` | `Array<JNIMatchingListener?>` |
| `JNIZBytes` | `serialize` | `Array<ByteArray?>` |
| `JNIZBytes` | `deserialize` | `Array<Any?>` |
| `JNIZBytesKotlin` | `serialize` | `Array<ByteArray?>` |
| `JNIZBytesKotlin` | `deserialize` | `Array<Any?>` |

### 2d. `zenoh-java` Callers

**Pattern for object-returning calls:**
```kotlin
val out = arrayOfNulls<JNISession>(1)
val err = JNISession.open(config, out)
if (err != null) throw ZError(err)
val jniSession = out[0]!!
```

**Pattern for void/Int calls:**
```kotlin
val err = jniSession.put(...)
if (err != null) throw ZError(err)
```

**Pattern for ByteArray calls:**
```kotlin
val out = arrayOfNulls<ByteArray>(1)
val err = jniSession.getZid(out)
if (err != null) throw ZError(err)
val zid = out[0]!!
```

**Files to update in `zenoh-java`:**
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Zenoh.kt`
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
2. **Update Rust JNI export functions** — one file at a time, changing return type to `jstring`, adding/changing `out` params, restoring doc comments.
3. **Update `zenoh-jni-runtime` private externals** — match new Rust signatures.
4. **Update `zenoh-jni-runtime` public wrapper functions** — add `LongArray`→wrapper bridging where needed.
5. **Update `zenoh-java` callers** — allocate typed out arrays, check `String?` return, throw `ZError`.

---

## Verification

1. **Build the project**: `./gradlew build` — must compile without errors.
2. **Run tests**: `./gradlew test` — all existing tests should pass, including `ZBytesInteropTests`.
3. **Confirm no exceptions from runtime**: grep `zenoh-jni-runtime/src` for `throw ZError` and `import io.zenoh.exceptions.ZError` — both should be absent.
4. **Confirm all JNI export functions return `jstring`**: grep `zenoh-jni/src` for `-> \*const` and `-> jint` patterns in `ViaJNI` functions — should be gone.
5. **Confirm doc comments restored**: run `git diff origin/common-jni...HEAD -- zenoh-jni/src/` and verify no `///` lines appear as deletions.

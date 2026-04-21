# Implementation Plan: JNI API — `String?` Error Return + `out` Parameter

## Context

The work branch (`zbobr_fix-75-throw-execptions-from-java`) already converted the JNI error channel from Rust-thrown exceptions to a typed-return + `error_out: JObjectArray` pattern. The task now requires a further redesign to a fully uniform contract:

- **Rust JNI functions**: return `jstring` (null = success, non-null = UTF-8 error message); the real return value goes into a caller-supplied `out` parameter.
- **`zenoh-jni-runtime`**: exposes error as `String?` through its public API. **Does not throw exceptions. Does not reference `ZError`.**
- **`zenoh-java`**: is the only layer that converts a non-null error string into a `ZError` and throws it.

Two Rust doc-comment blocks were also accidentally removed in prior commits and must be restored.

**Module dependency direction** (must not be violated):
```
zenoh-java → zenoh-jni-runtime → zenoh-jni (Rust)
```
`zenoh-jni-runtime` cannot import anything from `zenoh-java`; `ZError` lives in `zenoh-java` only.

---

## Part 1 — Restore Rust Doc Comments

Run `git diff origin/common-jni...HEAD` and re-add every removed `///` block verbatim, updating only phrases like "throws exception" → "returns error string" / "writes result to `out`". No new documentation should be added.

**Files affected:**
- `zenoh-jni/src/config.rs`
- `zenoh-jni/src/key_expr.rs`
- `zenoh-jni/src/session.rs`
- `zenoh-jni/src/publisher.rs`
- `zenoh-jni/src/querier.rs`
- `zenoh-jni/src/query.rs`
- `zenoh-jni/src/logger.rs`
- `zenoh-jni/src/scouting.rs`
- `zenoh-jni/src/zenoh_id.rs`
- `zenoh-jni/src/ext/advanced_publisher.rs`
- `zenoh-jni/src/ext/advanced_subscriber.rs`

---

## Part 2 — Add `return_error` Helper to `errors.rs`

**File:** `zenoh-jni/src/errors.rs`

Add:
```rust
pub(crate) fn return_error(env: &mut JNIEnv, msg: &str) -> jstring {
    env.new_string(msg)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}
```

The success sentinel is `JString::default().into_raw()` (a null pointer).

Remove `set_error_string` once all call sites are migrated, or keep it until the last call site is gone.

---

## Part 3 — Convert Rust JNI Functions

### General transformation rule

**Before (current):**
```rust
pub extern "C" fn Java_..._someViaJNI(
    mut env: JNIEnv, _class: JClass,
    /* inputs */,
    error_out: JObjectArray,
) -> TypedValue {
    do_op().unwrap_or_else(|e| {
        set_error_string(&mut env, &error_out, &e.to_string());
        DEFAULT_VALUE
    })
}
```

**After (new):**
```rust
pub extern "C" fn Java_..._someViaJNI(
    mut env: JNIEnv, _class: JClass,
    /* inputs */,
    out: JNI_OutType,   // omit for pure success/fail functions
) -> jstring {
    match do_op() {
        Ok(value) => {
            write_to_out(&mut env, &out, value);
            JString::default().into_raw()  // null = success
        }
        Err(e) => return_error(&mut env, &e.to_string()),
    }
}
```

### Out-parameter type mapping

| Kotlin return value | Kotlin out holder | Rust out type | Rust write method |
|---|---|---|---|
| `Long` (pointer/handle) | `LongArray(1)` | `JLongArray` | `env.set_long_array_region(&out, 0, &[val])` |
| `Int` | `IntArray(1)` | `JIntArray` | `env.set_int_array_region(&out, 0, &[val])` |
| `String` (non-null) | `Array<String?>(1){null}` | `JObjectArray` | `env.set_object_array_element(&out, 0, jstr)` |
| `ByteArray` | `Array<ByteArray?>(1){null}` | `JObjectArray` | `env.set_object_array_element(&out, 0, jbytes)` |
| `Any` | `Array<Any?>(1){null}` | `JObjectArray` | `env.set_object_array_element(&out, 0, jobject)` |
| pure success/fail | *(no out param)* | — | — |

### Special cases

- **`freePtrViaJNI` functions** — void and infallible, leave unchanged.
- **`insertJson5ViaJNI`** — currently returns `jint` (0/-1). Pure success/fail; drop `out`, return `jstring`.
- **`getJsonViaJNI`** — currently returns `jstring` as the real value. Change: write the JSON string into `out: JObjectArray`, return `jstring` error. Use `JObjectArray` out-type (element class: `java/lang/String`).
- **`getZidViaJNI`** — returns `ByteArray`; use `JObjectArray` out (`out[0]` = jbytearray).
- **`getPeersZidViaJNI` / `getRoutersZidViaJNI`** — return Java `ArrayList`; use `JObjectArray` out (`out[0]` = jobject ArrayList).
- **`zbytes.rs serializeViaJNI`** — returns `ByteArray`; use `JObjectArray` out.
- **`zbytes.rs deserializeViaJNI`** — returns `Any` (jobject); use `JObjectArray` out.
- **`zbytes_kotlin.rs`** — same patterns as `zbytes.rs`.

### Files to modify (Rust)

- `zenoh-jni/src/errors.rs`
- `zenoh-jni/src/config.rs`
- `zenoh-jni/src/key_expr.rs`
- `zenoh-jni/src/session.rs`
- `zenoh-jni/src/publisher.rs`
- `zenoh-jni/src/querier.rs`
- `zenoh-jni/src/query.rs`
- `zenoh-jni/src/logger.rs`
- `zenoh-jni/src/scouting.rs`
- `zenoh-jni/src/liveliness.rs`
- `zenoh-jni/src/zenoh_id.rs`
- `zenoh-jni/src/zbytes.rs`
- `zenoh-jni/src/zbytes_kotlin.rs`
- `zenoh-jni/src/ext/advanced_publisher.rs`
- `zenoh-jni/src/ext/advanced_subscriber.rs`

---

## Part 4 — Convert `zenoh-jni-runtime` Kotlin

### General transformation rule

**Before (current):**
```kotlin
// External
private external fun someViaJNI(/* inputs */, error: Array<String?>): TypedValue?

// Public API
fun someOp(/* inputs */, error: Array<String?>): TypedValue? =
    someViaJNI(/* inputs */, error)
```

**After (new):**
```kotlin
// External  
private external fun someViaJNI(/* inputs */, out: OutType): String?

// Public API — no exceptions, no ZError reference
fun someOp(/* inputs */, out: OutType): String? = someViaJNI(/* inputs */, out)
```

The runtime is a thin type-safe passthrough. All error-to-exception conversion happens one layer up in `zenoh-java`.

### Files to modify (commonMain)

- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIConfig.kt`
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIKeyExpr.kt`
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIPublisher.kt`
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIQuerier.kt`
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIQuery.kt`
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNILogger.kt`
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIScout.kt`
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIZenohId.kt`
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedPublisher.kt`
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedSubscriber.kt`

### Files to modify (jvmAndAndroidMain)

- `zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytes.kt`
- `zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.kt`

New signatures for `JNIZBytes`:
```kotlin
fun serialize(any: Any, type: Type, out: Array<ByteArray?>): String? = serializeViaJNI(any, type, out)
fun deserialize(bytes: ByteArray, type: Type, out: Array<Any?>): String? = deserializeViaJNI(bytes, type, out)
private external fun serializeViaJNI(any: Any, type: Type, out: Array<ByteArray?>): String?
private external fun deserializeViaJNI(bytes: ByteArray, type: Type, out: Array<Any?>): String?
```

Same pattern for `JNIZBytesKotlin` (replacing `Type` with `KType`).

---

## Part 5 — Update `zenoh-java` Wrappers

**Rule:** `zenoh-java` is the ONLY layer that throws `ZError`. Pattern:

```kotlin
// Before
val error = arrayOfNulls<String>(1)
val result = jniRuntime.someOp(/* inputs */, error)
    ?: throw ZError(error[0] ?: "fallback message")

// After
val out = LongArray(1)   // or appropriate holder type
jniRuntime.someOp(/* inputs */, out)?.let { throw ZError(it) }
val result = out[0]
```

For pure success/fail functions (no `out`):
```kotlin
// After
jniRuntime.someOp(/* inputs */)?.let { throw ZError(it) }
```

### Files to modify (commonMain)

- `zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Logger.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Zenoh.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/config/ZenohId.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/keyexpr/KeyExpr.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/liveliness/Liveliness.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/pubsub/Publisher.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/query/Querier.kt`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/query/Query.kt`

### Files to modify (jvmAndAndroidMain)

- `zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerializer.kt`
- `zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZDeserializer.kt`

New pattern for `ZSerializer`:
```kotlin
val out = arrayOfNulls<ByteArray>(1)
JNIZBytes.serialize(t as Any, type, out)?.let { throw ZError(it) }
return ZBytes(out[0] ?: throw ZError("Serialization returned null"))
```

---

## Part 6 — Verify Module Boundary

After migration, verify:
- `grep -r "ZError" zenoh-jni-runtime/src/` → zero results
- `grep -r "throw\|@Throws" zenoh-jni-runtime/src/` → zero results
- `zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt` is the sole `ZError` definition

---

## Verification

1. **Rust compile:** `cargo build` inside `zenoh-jni/` — confirms JNI signatures compile.
2. **Full build:** `./gradlew build` — Rust + Kotlin compilation across all modules.
3. **Tests:** `./gradlew test` — covers JNI paths including `ZBytesInteropTests.kt` and `ZBytesTests.java`.
4. **Grep check:** `grep -r "set_error_string\|error_out" zenoh-jni/src/` → zero results after migration.
5. **Smoke test:** Open session, put/get data — confirm errors surface as `ZError` thrown only in `zenoh-java`.
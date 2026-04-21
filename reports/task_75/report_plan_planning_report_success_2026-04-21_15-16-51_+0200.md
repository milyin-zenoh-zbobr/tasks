# Implementation Plan: JNI API Redesign — `String?` Return + `out` Parameter

## Context

The `zenoh-jni-runtime` crate currently throws Java exceptions from Rust JNI code. The task is to eliminate that, making the JNI API uniform: every native function returns `String?` (null = success, non-null = error message), and the real return value is written into a caller-supplied `out` parameter. Exception throwing and error-type export is moved entirely to `zenoh-java`.

The work branch (`zbobr_fix-75-throw-execptions-from-java`) has already converted the API from Rust-thrown exceptions to a typed-return + `error: Array<String?>` out-parameter pattern. The remaining work is to flip to the **final** uniform contract: `String?` return for error, typed `out` param for the real value.

A previous adversarial review (ctx_rec_3) identified that the zbytes JVM/Android surface (`JNIZBytes.kt`, `JNIZBytesKotlin.kt`, `ZSerializer.kt`, `ZDeserializer.kt`) was missing from the prior plan. This plan includes all surfaces.

Two doc-comment blocks were also accidentally removed from Rust source files; those must be restored.

---

## Target API Contract

### Rust JNI function signature (new)
```
pub extern "C" fn Java_...(
    mut env: JNIEnv,
    _class: JClass,
    // ... input params ...
    out: <JNI_out_type>,   // typed out-parameter for real return value (omit when pure success/fail)
) -> jstring               // null ptr = success; non-null = UTF-8 error string
```

### Kotlin runtime (`zenoh-jni-runtime`) external declaration (new)
```kotlin
private external fun someViaJNI(
    /* input params */,
    out: OutType            // last parameter (omit when pure success/fail)
): String?                  // null = success, non-null = error message
```

### Kotlin wrapper in `zenoh-jni-runtime` (new)
```kotlin
fun someOp(/* params */): ReturnType {
    val out = LongArray(1)   // or appropriate holder
    someViaJNI(/* params */, out)?.let { throw ZError(it) }
    return ReturnType(out[0])
}
```

### Kotlin caller in `zenoh-java` (new)
```kotlin
val result = jniRuntime.someOp(/* params */)  // ZError is thrown from runtime if needed
```
_(zenoh-java no longer needs to unwrap `error[0]` or check null returns.)_

---

## Out-Parameter Type Mapping

| Kotlin return value | Kotlin `out` holder | Rust `out` type | Rust write |
|---------------------|---------------------|-----------------|------------|
| `Long` (pointer)    | `LongArray(1)`      | `JLongArray`    | `env.set_long_array_region(out, 0, &[val])` |
| `Int`               | `IntArray(1)`       | `JIntArray`     | `env.set_int_array_region(out, 0, &[val])` |
| `String?`           | `Array<String?>(1){null}` | `JObjectArray` | `env.set_object_array_element(out, 0, jstr)` |
| `ByteArray?`        | `Array<ByteArray?>(1){null}` | `JObjectArray` | `env.set_object_array_element(out, 0, jbytes)` |
| `Any?`              | `Array<Any?>(1){null}` | `JObjectArray` | `env.set_object_array_element(out, 0, jobject)` |
| pure success/fail   | *(no out param)*    | —               | — |

---

## Part 1 — Restore Doc Comment Blocks

**Why:** Prior commits accidentally removed `///` Rust doc-comment blocks from multiple `.rs` files.

**How:** Run `git diff origin/common-jni...HEAD` and identify all removed lines beginning with `///`. Re-add those blocks verbatim, updating only references to "throws exception" → "returns error string" / "writes result to `out`". Do not add new documentation; only restore what was removed.

**Files affected (from diff):**
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

## Part 2 — Add Error Helper to `errors.rs`

Add a `return_error` helper alongside `set_error_string`:

```rust
pub(crate) fn return_error(env: &mut JNIEnv, msg: &str) -> jstring {
    env.new_string(msg)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}
```

Success is always `JString::default().into_raw()` (null pointer).

Remove or deprecate `set_error_string` once all call sites are migrated.

**File:** `zenoh-jni/src/errors.rs`

---

## Part 3 — Convert All Rust JNI Functions

For each exported function in every Rust JNI file:

1. **Add `out` parameter** of the appropriate JNI type (from mapping table above).  
   Exception: pure success/fail functions (e.g., `declare`/`undeclare` with no meaningful return value) take no `out` param.
2. **Change return type** to `jstring`.
3. **On success:** write value into `out`, return `JString::default().into_raw()`.
4. **On error:** return `return_error(&mut env, &err.to_string())`.
5. **Remove** the old `error_out: JObjectArray` parameter and the `set_error_string` call.

**Files to modify (Rust):**
- `zenoh-jni/src/errors.rs` — add `return_error`
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
- `zenoh-jni/src/zbytes.rs`  ← previously missing from plan
- `zenoh-jni/src/zbytes_kotlin.rs`  ← previously missing from plan
- `zenoh-jni/src/ext/advanced_publisher.rs`
- `zenoh-jni/src/ext/advanced_subscriber.rs`

**Special cases:**
- `freePtrViaJNI` functions — void and infallible, leave unchanged.
- `getZidViaJNI` — returns `ByteArray?`; use `JObjectArray` out, `env.set_object_array_element`.
- `getPeersZidViaJNI` / `getRoutersZidViaJNI` — return Java `ArrayList` object; use `JObjectArray` out.
- `zbytes.rs serializeViaJNI` — returns `ByteArray?`; use `JObjectArray` out.
- `zbytes.rs deserializeViaJNI` — returns `Any?` (jobject); use `JObjectArray` out.
- `zbytes_kotlin.rs serializeViaJNI` / `deserializeViaJNI` — same pattern as zbytes.rs.

---

## Part 4 — Convert All Kotlin Runtime Declarations

### commonMain (`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/`)

For each `private external fun`:
1. Replace `error: Array<String?>` with `out: <OutType>` as the last parameter.
2. Change return type to `String?`.
3. Update the public wrapper method:
   - Create the holder: `val out = LongArray(1)` (or appropriate type).
   - Call: `someViaJNI(/* inputs */, out)?.let { throw ZError(it) }`.
   - Return from `out[0]` (or `out` as needed).

**Files:**
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

### jvmAndAndroidMain (`zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/`)

Same transformation, applied to zbytes serialization surfaces:

**`JNIZBytes.kt`** (new signatures):
- `serialize(any: Any, type: Type, out: Array<ByteArray?>): String?`
- `deserialize(bytes: ByteArray, type: Type, out: Array<Any?>): String?`

**`JNIZBytesKotlin.kt`** (new signatures):
- `serialize(any: Any, kType: KType, out: Array<ByteArray?>): String?`
- `deserialize(bytes: ByteArray, kType: KType, out: Array<Any?>): String?`

Public wrapper methods follow the same pattern: allocate holder, call external, throw on non-null result, return holder value.

**Files:**
- `zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytes.kt`  ← previously missing
- `zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.kt`  ← previously missing

---

## Part 5 — Update `zenoh-java` Wrappers

The `zenoh-java` layer wraps `zenoh-jni-runtime`. Because the runtime now throws `ZError` internally, the zenoh-java wrappers no longer need:
- `arrayOfNulls<String>(1)` error holders
- null/negative-value checks on return values
- `error[0] ?: "..."` fallback strings

Update each file to simply call the runtime method and propagate any `ZError` thrown.

**commonMain files:**
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

**jvmAndAndroidMain files (zbytes surface — previously missing):**
- `zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerializer.kt`
- `zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZDeserializer.kt`

---

## Part 6 — Exception Export Location

After the migration:
- `zenoh-jni-runtime` no longer exports or throws `ZError`.
- `zenoh-java` owns `ZError` and is responsible for throwing it.
- Verify that `zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt` exists and is the sole definition.

---

## Verification

1. **Compile Rust:** `cargo build` in `zenoh-jni/` — confirms JNI signatures compile.
2. **Full build:** `./gradlew build` — triggers Rust + Kotlin compilation across all modules.
3. **Test suite:** `./gradlew test` — existing tests cover JNI paths including zbytes interop (`ZBytesInteropTests.kt`, `ZBytesTests.java`).
4. **Smoke test:** Open a session, perform put/get, confirm no exceptions originate from `zenoh-jni-runtime`; confirm errors propagate as `String?` through to `ZError` in `zenoh-java`.
5. **Grep check:** `grep -r "throw_exception\|error_out\|set_error_string" zenoh-jni/src/` should return zero results after migration.

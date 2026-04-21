# Implementation Plan: JNI API Uniformity + Restore Help Blocks

## Context

The work branch `zbobr_fix-75-throw-execptions-from-java` already converted the JNI error-reporting mechanism from Rust-thrown exceptions to an `error_out: JObjectArray` out-parameter. Two corrections are required:

1. **Restore accidentally removed Rust doc comment blocks** (`///` style) from multiple `.rs` files.
2. **Uniform API**: Change every JNI native function so that the *return type* is always `String?` (null = success, non-null = error message), and the *real return value* is written into a typed `out` parameter passed by the caller.

This makes the API completely uniform and removes the need for callers (zenoh-kotlin or zenoh-java) to inspect typed return values to distinguish success from failure.

---

## Part 1 — Restore Help Blocks

Files with removed `///` doc comments (identified via `git diff origin/common-jni...HEAD`):

| File | Scope |
|------|-------|
| `zenoh-jni/src/config.rs` | 7 doc blocks before each exported function |
| `zenoh-jni/src/key_expr.rs` | 9 doc blocks (functions + `process_kotlin_key_expr`) |
| `zenoh-jni/src/session.rs` | Multiple blocks including open-session variants |
| `zenoh-jni/src/publisher.rs` | 43 removed doc lines |
| `zenoh-jni/src/querier.rs` | 25 removed doc lines |
| `zenoh-jni/src/query.rs` | 77 removed doc lines |
| `zenoh-jni/src/logger.rs` | 16 removed doc lines |
| `zenoh-jni/src/scouting.rs` | 1 removed doc line |
| `zenoh-jni/src/zenoh_id.rs` | 1 removed doc line |
| `zenoh-jni/src/ext/advanced_publisher.rs` | 7 removed doc lines |
| `zenoh-jni/src/ext/advanced_subscriber.rs` | 6 removed doc lines |

**Action**: Re-add the doc comments from the original `origin/common-jni` code, updated to describe the **new** API (i.e., references to "throws exception" become "sets error string" or "returns error string"; references to return-value semantics are updated). The original text for each block is visible in `git diff origin/common-jni...HEAD` as removed `-` lines.

---

## Part 2 — New JNI API Convention

### Unified pattern

**Rust signature (new):**
```rust
pub extern "C" fn Java_..._someViaJNI(
    mut env: JNIEnv,
    _class: JClass,
    // ... input params ...
    out: <typed_out_array>,  // last parameter, receives real return value
) -> jstring {              // null ptr = success; non-null = error string
    match do_operation() {
        Ok(value) => {
            // write value into out
            JString::default().as_raw()  // null = success
        }
        Err(err) => env.new_string(&err.to_string())
                        .map(|s| s.as_raw())
                        .unwrap_or(std::ptr::null_mut())
    }
}
```

**Kotlin external function (new):**
```kotlin
private external fun someViaJNI(
    // ... input params ...
    out: <OutType>   // last parameter
): String?           // null = success, non-null = error message
```

**Kotlin wrapper (new):**
```kotlin
fun someOperation(...): ResultType {
    val out = LongArray(1)  // or appropriate type
    someViaJNI(..., out)?.let { throw ZError(it) }
    return ResultType(out[0])
}
```

### Out-parameter type mapping

| Current return type | Kotlin `out` type | Rust `out` type | Rust setter |
|---------------------|-------------------|-----------------|-------------|
| `Long` (pointer) | `LongArray` | `JLongArray` | `env.set_long_array_region(out, 0, &[val])` |
| `Int` (bool/ordinal) | `IntArray` | `JIntArray` | `env.set_int_array_region(out, 0, &[val])` |
| `String?` | `Array<String?>` | `JObjectArray` | `env.set_object_array_element(out, 0, jstr)` |
| `ByteArray?` | `Array<ByteArray?>` | `JObjectArray` | `env.set_object_array_element(out, 0, jbytes)` |
| `List<ByteArray>?` | `Array<List<ByteArray>?>` | `JObjectArray` | `env.set_object_array_element(out, 0, jobject)` |
| pure success/fail (`Int` 0/-1) | *none* — drop `out`, return `String?` only | — | — |

### Add helper to `errors.rs`

Add a `return_error` helper function alongside the existing `set_error_string`:
```rust
pub(crate) fn return_error(env: &mut JNIEnv, msg: &str) -> jstring {
    env.new_string(msg)
        .map(|s| s.as_raw())
        .unwrap_or(std::ptr::null_mut())
}
```
This is used by all functions to produce the error return value. Success is always `JString::default().as_raw()` (null).

---

## Part 3 — File-by-file Changes

### Rust files (`zenoh-jni/src/`)

Each exported JNI function in the following files needs the same transformation:
- Replace `error_out: JObjectArray` with typed `out: <JType>` (where meaningful return exists)
- Change return type from `*const T` / `jstring` / `jint` / `jbyteArray` / `jobject` to `jstring`
- On success: write value to `out`, return `JString::default().as_raw()`
- On error: return `return_error(&mut env, &err.to_string())`
- For pure success/fail functions: remove `out` parameter entirely, return `String?`

**Files to modify:**
- `zenoh-jni/src/errors.rs` — add `return_error` helper
- `zenoh-jni/src/config.rs` — 6 exported functions (loadDefault, loadConfigFile, loadJson, loadYaml, getJson, insertJson5)
- `zenoh-jni/src/key_expr.rs` — 7 exported functions
- `zenoh-jni/src/session.rs` — ~18 exported functions
- `zenoh-jni/src/publisher.rs` — all exported functions
- `zenoh-jni/src/querier.rs` — all exported functions
- `zenoh-jni/src/query.rs` — all exported functions
- `zenoh-jni/src/logger.rs` — all exported functions
- `zenoh-jni/src/scouting.rs` — all exported functions
- `zenoh-jni/src/liveliness.rs` — all exported functions
- `zenoh-jni/src/zenoh_id.rs` — all exported functions
- `zenoh-jni/src/zbytes.rs` — all exported functions
- `zenoh-jni/src/zbytes_kotlin.rs` — all exported functions
- `zenoh-jni/src/ext/advanced_publisher.rs` — all exported functions
- `zenoh-jni/src/ext/advanced_subscriber.rs` — all exported functions

`freePtrViaJNI` functions (void, infallible) are unchanged.

### Kotlin runtime files (`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/`)

Update all `private external fun` declarations and their corresponding public wrapper methods:
- `JNIConfig.kt` — 6 functions
- `JNIKeyExpr.kt` — 7 functions
- `JNISession.kt` — ~18 functions
- `JNIPublisher.kt`
- `JNIQuerier.kt`
- `JNIQuery.kt`
- `JNILogger.kt`
- `JNIScout.kt`
- `JNIZenohId.kt`
- `JNIAdvancedPublisher.kt`
- `JNIAdvancedSubscriber.kt`

### zenoh-java wrapper files (`zenoh-java/src/commonMain/kotlin/io/zenoh/`)

Adapt callers to the new JNI-runtime API. The pattern `result ?: throw ZError(error[0] ?: "...")` becomes `err?.let { throw ZError(it) }` plus reading `out[0]`:
- `Config.kt`
- `keyexpr/KeyExpr.kt`
- `Session.kt`
- `pubsub/Publisher.kt`
- `query/Querier.kt`
- `query/Query.kt`
- `Logger.kt`
- `Zenoh.kt`
- `config/ZenohId.kt`
- `liveliness/Liveliness.kt`

---

## Part 4 — Notable Edge Cases

1. **`freePtrViaJNI` functions**: These are void and infallible — no change to signature needed.
2. **`undeclareKeyExprViaJNI`**: Currently returns nothing. Verify whether it can fail; if not, leave as-is.
3. **`closeSessionViaJNI`**: Same as above.
4. **`getPeersZidViaJNI` / `getRoutersZidViaJNI`**: Return a Java ArrayList (jobject). The out parameter in Kotlin is `Array<List<ByteArray>?>` backed by a `JObjectArray` in Rust; set via `env.set_object_array_element(out, 0, array_list_object)`.
5. **`getZidViaJNI`**: Returns `ByteArray`. Out is `Array<ByteArray?>` in Kotlin; set via `env.set_object_array_element(out, 0, jbytes)`.

---

## Verification

1. **Build**: `./gradlew build` (triggers Rust + Kotlin compilation)
2. **Tests**: `./gradlew test` — existing test suite covers the JNI paths
3. **Manual smoke test**: Open a session, put/get data, close — confirm no exceptions thrown from zenoh-jni-runtime and errors propagate correctly as `String?` returns

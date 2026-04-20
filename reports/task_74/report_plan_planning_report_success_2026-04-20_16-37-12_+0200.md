# Plan: Throw Exceptions at Java Level Instead of Rust JNI Level

## Context

Currently, `zenoh-jni` (the Rust JNI bridge) throws Java exceptions directly from Rust using `throw_exception!` macro (~40 call sites). This requires `zenoh-kotlin` (a separate library that reuses the same JNI runtime) to wrap every JNI call in `runCatching` to catch exceptions. The goal is to:

1. Export `JNIError` publicly from the Rust crate (in a `jni` submodule namespace)
2. Remove all exception-throwing from Rust JNI functions; make them return error-indicator values instead
3. Have Kotlin (zenoh-java) side detect errors and throw `ZError`

**Destination branch:** `main`  
**Work branch:** `zbobr_fix-74-throw-exceptions-on-java-level`

## Design: Thread-local Error Storage

**Why this approach:** JNI function return types are constrained (pointer/bool/int/void). A thread-local stores the error message independent of return type, allowing all JNI functions to keep their natural return type while signaling errors via a sentinel value. This is the standard pattern for JNI error communication without exceptions.

### Error Communication per Return Type

| JNI Return Type | Error Sentinel | Error Message |
|---|---|---|
| `*const T` (pointer/Long) | 0 / null | thread-local |
| `void` → **`jlong`** | 1 | thread-local |
| `jstring` | null | thread-local |
| `jboolean` | `false` (ambiguous!) | thread-local always read |
| `jint` | -1 | thread-local |
| `jobject` / `jbyteArray` | null | thread-local |

For `jboolean` functions (`intersectsViaJNI`, `includesViaJNI`): the caller must always read and check the thread-local after the call, since `false` is a valid non-error result.

---

## Step 1: Rust — Refactor `errors.rs`

**File:** `zenoh-jni/src/errors.rs`

- Rename `ZError` → `JNIError`, change visibility from `pub(crate)` to `pub`
- Rename `ZResult<T>` → `JNIResult<T>`, change visibility to `pub`  
- Remove `throw_on_jvm` method (no longer needed)
- Remove `throw_exception!` macro
- Keep `zerror!` macro (still used internally)
- Add thread-local error storage:

```rust
thread_local! {
    static LAST_JNI_ERROR: RefCell<Option<String>> = RefCell::new(None);
}
pub fn set_last_jni_error(msg: impl Into<String>) { ... }
pub fn take_last_jni_error() -> Option<String> { ... }
```

- Add a `pub mod jni` re-export so other Rust crates can reference `JNIError` in the `jni` namespace:

```rust
pub mod jni {
    pub use super::JNIError;
    pub use super::JNIResult;
}
```

- Update all internal crate usages: `ZError` → `JNIError`, `ZResult` → `JNIResult`

---

## Step 2: Rust — Add `getAndClearLastError` JNI Function

Add a new JNI-exported function (place in `errors.rs` or a new `jni_error.rs` module, register in `lib.rs`):

```rust
#[no_mangle]
pub extern "C" fn Java_io_zenoh_jni_JNIError_getAndClearLastErrorViaJNI(
    env: JNIEnv,
    _class: JClass,
) -> jstring {
    take_last_jni_error()
        .and_then(|msg| env.new_string(msg).ok())
        .map(|s| s.into_raw())
        .unwrap_or_else(|| JString::default().into_raw())
}
```

---

## Step 3: Rust — Remove `throw_exception!` from All JNI Functions

Affects files: `session.rs`, `publisher.rs`, `querier.rs`, `query.rs`, `queryable.rs`, `key_expr.rs`, `config.rs`, `scouting.rs`, `liveliness.rs`, `zbytes.rs`, `zenoh_id.rs`, `utils.rs`, `logger.rs`

**Pattern for pointer-returning functions** (already return null on error):
```rust
// Before:
.unwrap_or_else(|err| {
    throw_exception!(env, err);
    null()
})

// After:
.unwrap_or_else(|err| {
    set_last_jni_error(err.to_string());
    null()
})
```

**Pattern for void functions** (change return type to `jlong`):
```rust
// Before:
pub unsafe extern "C" fn Java_io_zenoh_jni_JNIPublisher_putViaJNI(...) {
    let _ = || -> JNIResult<()> { ... }()
        .map_err(|err| throw_exception!(env, err));
}

// After:
pub unsafe extern "C" fn Java_io_zenoh_jni_JNIPublisher_putViaJNI(...) -> jlong {
    || -> JNIResult<()> { ... }()
        .map_or_else(|err| { set_last_jni_error(err.to_string()); 1 }, |_| 0)
}
```

**Void JNI functions to change return type** (from `void` to `jlong`):
- `publisher.rs`: `putViaJNI`, `deleteViaJNI`
- `session.rs`: `putViaJNI`, `deleteViaJNI`, `getViaJNI`, `undeclareKeyExprViaJNI`
- `config.rs`: `insertJson5ViaJNI`
- `querier.rs`: `getViaJNI`
- `query.rs`: reply functions (check and update)
- `liveliness.rs`: `undeclareViaJNI`
- `logger.rs`: `startLogsViaJNI`

**`utils.rs` callback case** (`load_on_close` thread callback):
The `throw_exception!` in the `onClose` background callback context can't meaningfully propagate to Kotlin. Replace with `tracing::error!` log only (the exception was already likely lost in a background thread).

---

## Step 4: Kotlin — Add `JNIError` Object

**New file:** `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNIError.kt`

```kotlin
package io.zenoh.jni

import io.zenoh.ZenohLoad
import io.zenoh.exceptions.ZError

internal object JNIError {
    init { ZenohLoad }

    external fun getAndClearLastErrorViaJNI(): String?

    fun throwLastError(default: String = "JNI error"): Nothing =
        throw ZError(getAndClearLastErrorViaJNI() ?: default)
}
```

---

## Step 5: Kotlin — Update JNI Wrapper Functions to Throw ZError

Affects files: `JNISession.kt`, `JNIPublisher.kt`, `JNIConfig.kt`, `JNIKeyExpr.kt`, `JNIQuerier.kt`, `JNIQuery.kt`, `JNIQueryable.kt`, `JNISubscriber.kt`, `JNILiveliness.kt`, `JNILivelinessToken.kt`, `JNIScout.kt`, `JNIZBytes.kt`, `JNIZenohId.kt`

**Pattern for pointer-returning functions:**
```kotlin
// Before:
@Throws(ZError::class)
private external fun openSessionViaJNI(configPtr: Long): Long

fun open(config: Config): JNISession {
    val sessionPtr = openSessionViaJNI(config.jniConfig.ptr) // could throw ZError from Rust
    return JNISession(sessionPtr)
}

// After:
private external fun openSessionViaJNI(configPtr: Long): Long // no longer throws from Rust

@Throws(ZError::class)
fun open(config: Config): JNISession {
    val sessionPtr = openSessionViaJNI(config.jniConfig.ptr)
    if (sessionPtr == 0L) JNIError.throwLastError("Failed to open session")
    return JNISession(sessionPtr)
}
```

**Pattern for void → Long functions:**
```kotlin
// Before:
@Throws(ZError::class)
private external fun putViaJNI(...): Unit

// After:
private external fun putViaJNI(...): Long  // 0=success, 1=error

@Throws(ZError::class)
fun put(...) {
    val result = putViaJNI(...)
    if (result != 0L) JNIError.throwLastError("Failed to put")
}
```

**Pattern for boolean-returning functions** (`intersects`, `includes`):
```kotlin
// Always read thread-local after call
fun intersects(other: KeyExpr): Boolean {
    val result = intersectsViaJNI(...)
    val err = JNIError.getAndClearLastErrorViaJNI()
    if (err != null) throw ZError(err)
    return result
}
```

Remove `@Throws(ZError::class)` from the `private external fun` declarations (they no longer throw from Rust), but keep `@Throws(ZError::class)` on the public wrapper methods (they now throw from Kotlin).

---

## Critical Files

- `zenoh-jni/src/errors.rs` — central change, thread-local, JNIError rename
- `zenoh-jni/src/session.rs` — most JNI functions (~15 throw_exception! calls)
- `zenoh-jni/src/publisher.rs`, `querier.rs`, `query.rs`, `scouting.rs`, `liveliness.rs`, `key_expr.rs`, `config.rs`, `zbytes.rs`, `zenoh_id.rs`, `logger.rs`, `utils.rs`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNIError.kt` — new file
- All `JNI*.kt` files in `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/`

---

## Verification

1. **Rust build:** `cd zenoh-jni && cargo build` — must compile with no errors
2. **Kotlin build:** `./gradlew build` from project root  
3. **Tests:** `./gradlew test` — existing JVM tests should still pass (session open/close, put/get, subscribe, publish)
4. **Error propagation test:** Manually verify that a bad config path throws `ZError` from Kotlin (not from native code) by checking the stack trace
5. **No `throw_exception!` remaining:** `grep -r "throw_exception!" zenoh-jni/src/` should return empty

The plan is complete and submitted. Here's a summary of what was designed:

## Plan Summary

**Problem:** Rust JNI code throws Java exceptions directly via `throw_exception!` (~40 sites), forcing `zenoh-kotlin` to wrap every JNI call in `runCatching`.

**Solution: Thread-local error storage**

1. **Rust `errors.rs`**: Rename `ZError` → `JNIError` (public), add thread-local error storage, add `pub mod jni { pub use JNIError; }`, remove `throw_exception!` macro

2. **New Rust JNI function**: `Java_io_zenoh_jni_JNIError_getAndClearLastErrorViaJNI()` — lets Kotlin retrieve the stored error message

3. **All Rust JNI files**: Replace `throw_exception!(env, err)` with `set_last_jni_error(err.to_string())` + return sentinel. Void-returning functions gain `-> jlong` return type (0=success, 1=error)

4. **New Kotlin `JNIError.kt`**: Object with `getAndClearLastErrorViaJNI()` and `throwLastError()` helper

5. **All `JNI*.kt` files**: After each JNI call, check the sentinel value; if error, call `JNIError.throwLastError()` to throw `ZError` from Kotlin
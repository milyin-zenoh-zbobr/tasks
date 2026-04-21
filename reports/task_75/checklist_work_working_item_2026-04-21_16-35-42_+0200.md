Replace the `set_error_string` function in `zenoh-jni/src/errors.rs` with `make_error_jstring`.

The new function signature:
```rust
pub(crate) fn make_error_jstring(env: &mut JNIEnv, msg: &str) -> jstring {
    match env.new_string(msg) {
        Ok(s) => s.into_raw(),
        // If new_string() fails (OOM), a Java OutOfMemoryError is already pending in the JVM
        // and will propagate to the caller. Returning null here is intentional.
        Err(_) => std::ptr::null_mut(),
    }
}
```

Also add a helper for success (null jstring):
```rust
pub(crate) fn jni_ok() -> jstring {
    std::ptr::null_mut()
}
```

Remove the `set_error_string` function and update imports (`JObjectArray` import removed if not needed).
Update all callers in all Rust files to use `make_error_jstring` instead of `set_error_string`. Note: callers will be updated as part of subsequent checklist items.
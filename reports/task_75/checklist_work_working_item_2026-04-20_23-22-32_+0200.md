Modify zenoh-jni/src/errors.rs:
1. Add `pub(crate) fn set_error_string(env: &mut JNIEnv, error_out: &JObjectArray, msg: &str)` that writes msg into error_out[0] via JNI set_object_array_element. Log failures with tracing::error! and swallow.
2. Remove the `KOTLIN_EXCEPTION_NAME` const and `throw_on_jvm()` method from ZError.
3. Keep ZError struct, zerror! macro, ZResult, and the throw_exception! macro definition (but it won't be called after all other phases complete).
Requires adding JObjectArray to imports in errors.rs.
Modify `zenoh-jni/src/zbytes_kotlin.rs` for serializeViaJNI and deserializeViaJNI:
- Add `error_out: JObjectArray` as last parameter to each function
- Replace `throw_exception!(env, err)` with `set_error_string(&mut env, &error_out, &err.to_string())`
- Update imports: add set_error_string, remove throw_exception
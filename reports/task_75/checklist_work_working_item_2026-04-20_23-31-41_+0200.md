Modify `zenoh-jni/src/scouting.rs` `Java_io_zenoh_jni_JNIScout_00024Companion_scoutViaJNI`:
- Add `error_out: JObjectArray` as last parameter
- Replace `throw_exception!(env, err); null()` with `set_error_string(&mut env, &error_out, &err.to_string()); null()`
- Update imports to include `set_error_string` from errors module
- Remove `throw_exception` from imports
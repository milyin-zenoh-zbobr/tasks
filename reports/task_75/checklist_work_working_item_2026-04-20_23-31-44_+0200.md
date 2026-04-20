Modify `zenoh-jni/src/ext/advanced_subscriber.rs`:
- Update all 4 exported functions 
- Add `error_out: JObjectArray` as last parameter
- Replace `throw_exception!(env, err)` with `set_error_string` calls
- Update imports
Modify `zenoh-jni/src/ext/advanced_publisher.rs`:
- Update all 5 exported functions (put, delete, declareMatchingListener, declareBackgroundMatchingListener, getMatchingStatus)
- Add `error_out: JObjectArray` as last parameter
- Replace all `throw_exception!(env, err)` and `.map_err(|err| throw_exception!(env, err))` with `set_error_string` calls
- Update return types and sentinels per plan conventions
- Update imports
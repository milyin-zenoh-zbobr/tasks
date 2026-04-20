Modify `zenoh-jni/src/zbytes.rs`:
- `Java_io_zenoh_jni_JNIZBytes_serializeViaJNI`: add `error_out: JObjectArray`, replace throw with set_error_string
- `Java_io_zenoh_jni_JNIZBytes_deserializeViaJNI`: add `error_out: JObjectArray`, replace throw with set_error_string
- Update imports: add JObjectArray import (may be there already), add set_error_string import, remove throw_exception
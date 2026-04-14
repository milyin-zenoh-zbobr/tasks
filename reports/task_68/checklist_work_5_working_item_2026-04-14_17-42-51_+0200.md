In `zenoh-jni/src/session.rs`:
1. Remove `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI` function (lines ~48-77 including doc comment).
2. Update the doc comment on the surviving `Java_io_zenoh_jni_JNISession_openSessionViaJNI` (around line 1227) to describe it as the canonical shared binding (not "instance-method variant for zenoh-kotlin compatibility").
Run the following verifications:

1. Build: `./gradlew build` — must compile without errors
2. Run tests: `./gradlew test` — all tests pass including ZBytesInteropTests
3. Confirm no exceptions from runtime: grep for `throw ZError` and `import io.zenoh.exceptions.ZError` in zenoh-jni-runtime/src — both must be absent
4. Confirm all JNI export functions return jstring: grep for `-> \*const`, `-> jint`, `-> jlong`, `-> jobject`, `-> jbyteArray` in ViaJNI functions in zenoh-jni/src — should be gone
5. Confirm no legacy error pattern: grep for `error: Array<String?>` in zenoh-jni-runtime/src — should be gone
6. Confirm doc comments restored: no `///` deletions in git diff
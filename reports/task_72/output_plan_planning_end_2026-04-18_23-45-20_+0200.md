The plan is ready. Here's a summary of the key changes from prior versions that address the three adversarial review issues:

1. **Serialization source-set mismatch**: Created a new `jvmAndAndroidMain` intermediate source set in zenoh-kotlin. Moved `ZSerialize.kt`/`ZDeserialize.kt` there (from commonMain) so they can directly call `JNIZBytesKotlin.serialize()` from zenoh-jni-runtime (which is also in `jvmAndAndroidMain`). The bridge wraps the returned `ByteArray` in `ZBytes(byteArray)`.

2. **isRemotePublication scope**: Removed only the native-bundling logic (jni-libs resource dir, local Cargo build gate). The signing gate `signing { isRequired = isRemotePublication }` is explicitly preserved for Maven Central publication.

3. **JNILiveliness**: Not deleted — it contains valuable callback adapter logic (Sample/Reply construction) that zenoh-jni-runtime doesn't duplicate. Instead, its `private external fun` declarations are removed and replaced with calls to zenoh-jni-runtime's `JNISession` liveliness methods.
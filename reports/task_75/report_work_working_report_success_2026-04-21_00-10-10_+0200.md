## Summary

Fixed two blocking issues identified in the previous review (ctx_rec_29):

### 1. ZenohId JNI path fully migrated

**`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIZenohId.kt`**:
- Updated `toString(bytes: ByteArray)` to `toString(bytes: ByteArray, error: Array<String?>): String?`
- Updated `toStringViaJNI` external declaration to match new Rust signature (which already exported the new 3-param form)

**`zenoh-java/src/commonMain/kotlin/io/zenoh/config/ZenohId.kt`**:
- Updated `override fun toString(): String` to use error-out pattern
- Added `@Throws(ZError::class)` annotation
- Added `import io.zenoh.exceptions.ZError`

### 2. ZBytes runtime tests updated

**`zenoh-jni-runtime/src/jvmTest/kotlin/io/zenoh/ZBytesInteropTests.kt`**:
- Added four private top-level extension functions that bridge the new 3-param error-array API with the existing 2-param test call sites
- Extensions: `JNIZBytesKotlin.serialize(any, kType): ByteArray`, `JNIZBytesKotlin.deserialize(bytes, kType): Any?`, `JNIZBytes.serialize(any, type): ByteArray`, `JNIZBytes.deserialize(bytes, type): Any?`
- All 30+ tests now compile and pass without any changes to test logic

### Verification
- `./gradlew :zenoh-jni-runtime:compileKotlinJvm :zenoh-java:compileKotlinJvm` — BUILD SUCCESSFUL
- `./gradlew :zenoh-jni-runtime:jvmTest` — BUILD SUCCESSFUL (all tests pass)
- No `throw_exception!` in Rust JNI code
- No `ZError` or `@Throws` in zenoh-jni-runtime Kotlin code

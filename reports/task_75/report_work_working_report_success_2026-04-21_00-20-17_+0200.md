## Fixed Issues from ctx_rec_31 Review

### 1. JNIZBytes/JNIZBytesKotlin serialize return type (ByteArray? instead of Any?)
- `zenoh-jni-runtime/.../JNIZBytes.kt`: Changed `serialize`/`serializeViaJNI` return type from `Any?` to `ByteArray?`
- `zenoh-jni-runtime/.../JNIZBytesKotlin.kt`: Changed `serialize`/`serializeViaJNI` return type from `Any?` to `ByteArray?`
- `zenoh-java/.../ext/ZSerializer.kt`: Removed unnecessary `as ByteArray` cast (now compile-time safe)
- `zenoh-jni-runtime/.../ZBytesInteropTests.kt`: Removed unnecessary `as ByteArray?` casts in test helper wrappers

### 2. Config.loadDefault() missing @Throws annotation
- `zenoh-java/.../Config.kt`: Added `@Throws(ZError::class)` to `loadDefault()` for consistency with all other factory methods and for Java interop correctness

### Verification
- `./gradlew :zenoh-jni-runtime:compileKotlinJvm :zenoh-java:compileKotlinJvm` — BUILD SUCCESSFUL
- `./gradlew :zenoh-jni-runtime:jvmTest` — BUILD SUCCESSFUL (all tests pass)

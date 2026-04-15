The review (ctx_rec_39) found that io.zenoh.exceptions.ZError is defined in both zenoh-jni-runtime and zenoh-java, causing duplicate class issues on JVM/Android.

Fix:
1. Delete zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt
2. Change `implementation(project(":zenoh-jni-runtime"))` to `api(project(":zenoh-jni-runtime"))` in zenoh-java/build.gradle.kts so ZError (which is part of zenoh-java's public ABI via @Throws) is properly re-exported.
3. Verify build still passes.
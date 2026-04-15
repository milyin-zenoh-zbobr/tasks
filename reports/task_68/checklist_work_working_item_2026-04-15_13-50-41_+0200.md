Create the zenoh-jni-runtime Gradle subproject:
1. Add `include(":zenoh-jni-runtime")` to settings.gradle.kts
2. Create zenoh-jni-runtime/build.gradle.kts (copy from zenoh-java/build.gradle.kts, adapt for runtime: owns buildZenohJni task, no serialization/dokka/guava deps, published as org.eclipse.zenoh:zenoh-jni-runtime)
3. Create source directory structure:
   - zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/
   - zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/
   - zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/callbacks/
   - zenoh-jni-runtime/src/jvmMain/kotlin/io/zenoh/
   - zenoh-jni-runtime/src/androidMain/kotlin/io.zenoh/
4. Add AndroidManifest.xml for Android target

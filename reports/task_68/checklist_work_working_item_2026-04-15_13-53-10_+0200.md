Verification steps:
1. `./gradlew :zenoh-jni-runtime:compileKotlinJvm` - runtime compiles
2. `./gradlew :zenoh-java:compileKotlinJvm` - zenoh-java compiles
3. `./gradlew :zenoh-java:test` - existing tests pass
4. Verify no io.zenoh.* facade imports in zenoh-jni-runtime (only io.zenoh.jni.*, io.zenoh.ZenohLoad, io.zenoh.Target allowed)
5. Verify JNI symbol shapes match Rust exports

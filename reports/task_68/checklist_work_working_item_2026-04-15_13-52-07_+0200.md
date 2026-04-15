Update zenoh-java/build.gradle.kts:
- Remove buildZenohJni Gradle task and buildZenohJNI function (moved to runtime)
- Remove native lib resources from jvmMain source set (packaged by runtime)
- Keep jvmTest resources (for running tests locally)
- Add: `implementation(project(":zenoh-jni-runtime"))`
- Keep all other dependencies (commons-net, guava, kotlin-serialization)
- Keep jvmArgs("-Djava.library.path=../zenoh-jni/target/$buildMode") for tests

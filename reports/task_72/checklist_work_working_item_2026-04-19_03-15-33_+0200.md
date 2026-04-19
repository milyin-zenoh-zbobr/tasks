settings.gradle.kts:
- Remove :zenoh-jni from include()
- Add gated composite build for zenoh-java submodule

Root build.gradle.kts:
- Remove org.mozilla.rust-android-gradle:plugin from buildscript deps

zenoh-kotlin/build.gradle.kts:
- Add zenoh-jni-runtime dependency in commonMain
- Add jvmAndAndroidMain intermediate source set
- Remove buildZenohJni task, buildZenohJNI() function, all Cargo/NDK wiring
- Remove jni-libs resource source dirs
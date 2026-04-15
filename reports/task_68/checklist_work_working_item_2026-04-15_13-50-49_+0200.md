Create ZenohLoad and Target files in zenoh-jni-runtime:
1. zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/ZenohLoad.kt - `public expect object ZenohLoad`
2. zenoh-jni-runtime/src/jvmMain/kotlin/io/zenoh/ZenohLoad.kt - Copy full actual implementation from zenoh-java's jvmMain/Zenoh.kt
3. zenoh-jni-runtime/src/androidMain/kotlin/io.zenoh/ZenohLoad.kt - `actual object ZenohLoad { System.loadLibrary("zenoh_jni") }`
4. zenoh-jni-runtime/src/jvmMain/kotlin/io/zenoh/Target.kt - Copy Target enum from zenoh-java's jvmMain/Target.kt

All as PUBLIC (not internal).

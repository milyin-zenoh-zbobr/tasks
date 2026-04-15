Create the full zenoh-jni-runtime module from scratch. Previous session claimed this was done (steps 1-9) but nothing was committed.

Files to create:
- settings.gradle.kts: add `include(":zenoh-jni-runtime")`
- zenoh-jni-runtime/build.gradle.kts: adapted from zenoh-java, owns cargo build, no serialization/dokka/guava
- zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt (moved from zenoh-java)
- zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/ZenohLoad.kt (public expect)
- zenoh-jni-runtime/src/jvmMain/kotlin/io/zenoh/ZenohLoad.kt (actual - full library loading)
- zenoh-jni-runtime/src/jvmMain/kotlin/io/zenoh/Target.kt (internal enum)
- zenoh-jni-runtime/src/androidMain/kotlin/io.zenoh/ZenohLoad.kt (actual - System.loadLibrary)
- All 5 callbacks (JNISubscriberCallback, JNIQueryableCallback, JNIGetCallback, JNIScoutCallback, JNIOnCloseCallback) - PUBLIC
- 2 new callbacks (JNIMatchingListenerCallback, JNISampleMissListenerCallback) - PUBLIC
- All JNI adapters made public/primitive-only: JNIConfig, JNIKeyExpr, JNISession, JNIPublisher, JNIQuery, JNIQuerier, JNIScout, JNILiveliness, JNISubscriber, JNIQueryable, JNILivelinessToken, JNIZenohId
- New adapters: JNIAdvancedPublisher, JNIAdvancedSubscriber, JNIMatchingListener, JNISampleMissListener
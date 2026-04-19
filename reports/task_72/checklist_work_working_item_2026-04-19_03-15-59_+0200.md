Delete all files under zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/ (including callbacks/ subdirectory):
- JNIAdvancedPublisher.kt, JNIAdvancedSubscriber.kt, JNIConfig.kt, JNIKeyExpr.kt
- JNILivelinessToken.kt, JNILogger.kt, JNIMatchingListener.kt, JNIPublisher.kt
- JNIQuerier.kt, JNIQuery.kt, JNIQueryable.kt, JNISampleMissListener.kt
- JNIScout.kt, JNISession.kt, JNISubscriber.kt, JNIZenohId.kt, JNIZBytes.kt
- callbacks/: JNIGetCallback.kt, JNIMatchingListenerCallback.kt, JNIOnCloseCallback.kt
  JNIQueryableCallback.kt, JNISampleMissListenerCallback.kt, JNIScoutCallback.kt, JNISubscriberCallback.kt

Also delete duplicate shared classes:
- zenoh-kotlin/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt
- zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt
- zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt (actual object ZenohLoad)
- zenoh-kotlin/src/androidMain/kotlin/io/zenoh/Zenoh.kt (actual object ZenohLoad)

Keep JNILiveliness.kt - it will be adapted in phase 3d.
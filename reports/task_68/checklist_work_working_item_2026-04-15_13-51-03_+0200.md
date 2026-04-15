Create all callback interfaces in zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/callbacks/:
- JNISubscriberCallback.kt (public fun interface, same signature as in zenoh-java)
- JNIQueryableCallback.kt (public)
- JNIGetCallback.kt (public)
- JNIScoutCallback.kt (public)
- JNIOnCloseCallback.kt (public)
- JNIMatchingListenerCallback.kt (NEW - `fun interface JNIMatchingListenerCallback { fun run(matching: Boolean) }`)
- JNISampleMissListenerCallback.kt (NEW - `fun interface JNISampleMissListenerCallback { fun run(zidLower: Long, zidUpper: Long, eid: Long, nb: Long) }`)

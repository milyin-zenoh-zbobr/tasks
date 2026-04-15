Create new files in zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/:
- JNIAdvancedPublisher.kt (JNIPublisher pattern: public val ptr, primitive put/delete/matchingListener etc.)
- JNIAdvancedSubscriber.kt (JNIPublisher pattern, includes history Bool)
- JNIMatchingListener.kt (simple, just close/freePtrViaJNI)
- JNISampleMissListener.kt (simple, just close/freePtrViaJNI)

Create simple JNI adapter classes in zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/:
- JNISubscriber.kt - `public class JNISubscriber(val ptr: Long) { fun close() { freePtrViaJNI(ptr) }; private external fun freePtrViaJNI(ptr: Long) }`
- JNIQueryable.kt - same pattern
- JNILivelinessToken.kt - keep companion pattern for undeclareViaJNI
- JNIZenohId.kt - public object, references ZenohLoad

All classes must be PUBLIC (not internal).

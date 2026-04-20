For all JNI adapter Kotlin files in zenoh-jni-runtime:
1. Remove @Throws(ZError::class) annotations
2. Remove import io.zenoh.exceptions.ZError
3. Add error: Array<String?> as last parameter to each external fun and public adapter method
4. Change return types: Unit->Int, Boolean->Int, String->String?, ByteArray->ByteArray?
5. For Long-returning wrapper methods that construct objects: check for 0L pointer and return null
6. Don't throw in runtime adapters - return sentinels

Files: JNISession.kt, JNIConfig.kt, JNIKeyExpr.kt, JNIPublisher.kt, JNIQuery.kt, JNIQuerier.kt, JNIScout.kt, JNILogger.kt, JNIAdvancedPublisher.kt, JNIAdvancedSubscriber.kt, JNIZenohId.kt, JNIZBytes.kt (jvmAndAndroidMain), JNIZBytesKotlin.kt (jvmAndAndroidMain)
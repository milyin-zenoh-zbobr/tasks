Update all JNI adapter files in zenoh-jni-runtime:
- JNISession.kt: remove @Throws(ZError), add error: Array<String?> param to all changed external funs
- JNIConfig.kt: same treatment
- JNIKeyExpr.kt: same
- JNIPublisher.kt: same
- JNIQuery.kt: same
- JNIQuerier.kt: same
- JNIScout.kt: same  
- JNILogger.kt: same
- JNIAdvancedPublisher.kt: same
- JNIAdvancedSubscriber.kt: same
- JNIZenohId.kt: same
- JNIZBytes.kt: same (jvmAndAndroidMain)
- JNIZBytesKotlin.kt: same

For each: remove import ZError, remove @Throws annotation, add error: Array<String?> param, change return types (Unit->Int, Boolean->Int, non-nullable String->String?, etc.)
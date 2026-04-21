Changes to `zenoh-jni/src/ext/advanced_publisher.rs`:
- `putViaJNI(...) -> jstring`: no out, void-like, remove error_out
- `deleteViaJNI(...) -> jstring`: same
- `declareMatchingListenerViaJNI(..., out: JLongArray) -> jstring`: write listener ptr to out[0]
- `declareBackgroundMatchingListenerViaJNI(...) -> jstring`: no out, void-like
- `getMatchingStatusViaJNI(..., out: JIntArray) -> jstring`: write 1/0 to out[0], return null on success

Update `JNIAdvancedPublisher.kt`:
```kotlin
fun put(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?): String? =
    putViaJNI(ptr, payload, encodingId, encodingSchema, attachment)

fun delete(attachment: ByteArray?): String? = deleteViaJNI(ptr, attachment)

fun declareMatchingListener(callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback, out: Array<JNIMatchingListener?>): String? {
    val rawOut = LongArray(1)
    val err = declareMatchingListenerViaJNI(ptr, callback, onClose, rawOut)
    if (err == null) out[0] = JNIMatchingListener(rawOut[0])
    return err
}

fun declareBackgroundMatchingListener(callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback): String? =
    declareBackgroundMatchingListenerViaJNI(ptr, callback, onClose)

fun getMatchingStatus(out: IntArray): String? = getMatchingStatusViaJNI(ptr, out)

private external fun putViaJNI(ptr: Long, payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?): String?
private external fun deleteViaJNI(ptr: Long, attachment: ByteArray?): String?
private external fun declareMatchingListenerViaJNI(ptr: Long, callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback, out: LongArray): String?
private external fun declareBackgroundMatchingListenerViaJNI(ptr: Long, callback: JNIMatchingListenerCallback, onClose: JNIOnCloseCallback): String?
private external fun getMatchingStatusViaJNI(ptr: Long, out: IntArray): String?
```

Update zenoh-java advanced publisher callers (AdvancedPublisher.kt if it exists, otherwise find callers) to use String? pattern.
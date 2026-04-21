Changes to `zenoh-jni/src/ext/advanced_subscriber.rs`:
- `declareDetectPublishersSubscriberViaJNI(..., out: JLongArray) -> jstring`: write subscriber ptr to out[0]
- `declareBackgroundDetectPublishersSubscriberViaJNI(...) -> jstring`: no out, void-like
- `declareSampleMissListenerViaJNI(..., out: JLongArray) -> jstring`: write listener ptr to out[0]
- `declareBackgroundSampleMissListenerViaJNI(...) -> jstring`: no out, void-like

Update `JNIAdvancedSubscriber.kt`:
```kotlin
fun declareDetectPublishersSubscriber(history: Boolean, callback: JNISubscriberCallback, onClose: JNIOnCloseCallback, out: Array<JNISubscriber?>): String? {
    val rawOut = LongArray(1)
    val err = declareDetectPublishersSubscriberViaJNI(ptr, history, callback, onClose, rawOut)
    if (err == null) out[0] = JNISubscriber(rawOut[0])
    return err
}

fun declareBackgroundDetectPublishersSubscriber(history: Boolean, callback: JNISubscriberCallback, onClose: JNIOnCloseCallback): String? =
    declareBackgroundDetectPublishersSubscriberViaJNI(ptr, history, callback, onClose)

fun declareSampleMissListener(callback: JNISampleMissListenerCallback, onClose: JNIOnCloseCallback, out: Array<JNISampleMissListener?>): String? {
    val rawOut = LongArray(1)
    val err = declareSampleMissListenerViaJNI(ptr, callback, onClose, rawOut)
    if (err == null) out[0] = JNISampleMissListener(rawOut[0])
    return err
}

fun declareBackgroundSampleMissListener(callback: JNISampleMissListenerCallback, onClose: JNIOnCloseCallback): String? =
    declareBackgroundSampleMissListenerViaJNI(ptr, callback, onClose)

private external fun declareDetectPublishersSubscriberViaJNI(..., out: LongArray): String?
private external fun declareBackgroundDetectPublishersSubscriberViaJNI(...): String?
private external fun declareSampleMissListenerViaJNI(..., out: LongArray): String?
private external fun declareBackgroundSampleMissListenerViaJNI(...): String?
```

Update zenoh-java advanced subscriber callers to use String? pattern.
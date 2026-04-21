Changes to `zenoh-jni/src/liveliness.rs`:
- `livelinessGetViaJNI(...) -> jstring`: no out, void-like
- `declareLivelinessTokenViaJNI(..., out: JLongArray) -> jstring`: write token ptr to out[0]
- `declareLivelinessSubscriberViaJNI(..., out: JLongArray) -> jstring`: write subscriber ptr to out[0]

Update `JNISession.kt` - add liveliness methods with new signatures:
```kotlin
fun declareLivelinessToken(jniKeyExpr: JNIKeyExpr?, keyExprString: String, out: Array<JNILivelinessToken?>): String? {
    val rawOut = LongArray(1)
    val err = declareLivelinessTokenViaJNI(sessionPtr, jniKeyExpr?.ptr ?: 0, keyExprString, rawOut)
    if (err == null) out[0] = JNILivelinessToken(rawOut[0])
    return err
}
fun declareLivelinessSubscriber(..., out: Array<JNISubscriber?>): String? { /* bridge pattern */ }
fun livelinessGet(...): String? { /* void-like */ }

private external fun declareLivelinessTokenViaJNI(sessionPtr: Long, keyExprPtr: Long, keyExprString: String, out: LongArray): String?
private external fun declareLivelinessSubscriberViaJNI(..., out: LongArray): String?
private external fun livelinessGetViaJNI(...): String?
```

Update zenoh-java `Liveliness.kt` callers to use `String?` pattern + throw ZError.
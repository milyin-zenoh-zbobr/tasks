Changes to `zenoh-jni/src/query.rs`:
- `replySuccessViaJNI(...) -> jstring`: no out, remove error_out
- `replyErrorViaJNI(...) -> jstring`: no out, remove error_out
- `replyDeleteViaJNI(...) -> jstring`: no out, remove error_out

Changes to `zenoh-jni/src/querier.rs`:
- `getViaJNI(...) -> jstring`: no out, remove error_out

Update `JNIQuery.kt`:
```kotlin
fun replySuccess(...): String? = replySuccessViaJNI(...)
fun replyError(...): String? = replyErrorViaJNI(...)
fun replyDelete(...): String? = replyDeleteViaJNI(...)
private external fun replySuccessViaJNI(...): String?  // no error Array param
private external fun replyErrorViaJNI(...): String?
private external fun replyDeleteViaJNI(...): String?
```

Update `JNIQuerier.kt`:
```kotlin
fun get(...): String? = getViaJNI(...)
private external fun getViaJNI(...): String?  // no error Array param
```

Update zenoh-java `Query.kt` and `Querier.kt`:
- Check `String?` return and throw `ZError` if non-null
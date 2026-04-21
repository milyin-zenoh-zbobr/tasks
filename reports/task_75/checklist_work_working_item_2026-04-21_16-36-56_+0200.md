Change JNI functions in `zenoh-jni/src/publisher.rs` to return `jstring` (void-like, no out param).

- `putViaJNI(ptr, payload, encoding_id, encoding_schema, attachment) -> jstring`: remove error_out, return null on success, error message on failure
- `deleteViaJNI(ptr, attachment) -> jstring`: same pattern

Update `JNIPublisher.kt`:
```kotlin
fun put(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?): String? =
    putViaJNI(ptr, payload, encodingId, encodingSchema, attachment)

fun delete(attachment: ByteArray?): String? = deleteViaJNI(ptr, attachment)

private external fun putViaJNI(ptr: Long, valuePayload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?): String?
private external fun deleteViaJNI(ptr: Long, attachment: ByteArray?): String?
```

Update `Publisher.kt` in zenoh-java:
```kotlin
fun put(payload: IntoZBytes) {
    val jni = jniPublisher ?: throw publisherNotValid
    val err = jni.put(payload.into().bytes, encoding.id, encoding.schema, null)
    if (err != null) throw ZError(err)
}
fun delete(options: DeleteOptions = DeleteOptions()) {
    val jni = jniPublisher ?: throw publisherNotValid
    val err = jni.delete(options.attachment?.into()?.bytes)
    if (err != null) throw ZError(err)
}
```
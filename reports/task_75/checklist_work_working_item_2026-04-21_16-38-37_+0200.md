Changes to `zenoh-jni/src/zbytes.rs`:
- `serializeViaJNI(any, type, out: JObjectArray) -> jstring`: write byte array to out[0], return null on success
- `deserializeViaJNI(bytes, type, out: JObjectArray) -> jstring`: write object to out[0], return null on success

Changes to `zenoh-jni/src/zbytes_kotlin.rs`:
- `serializeViaJNI(any, kType, out: JObjectArray) -> jstring`: same pattern
- `deserializeViaJNI(bytes, kType, out: JObjectArray) -> jstring`: same pattern

Update `JNIZBytes.kt`:
```kotlin
fun serialize(any: Any, type: Type, out: Array<ByteArray?>): String? = serializeViaJNI(any, type, out)
fun deserialize(bytes: ByteArray, type: Type, out: Array<Any?>): String? = deserializeViaJNI(bytes, type, out)
@JvmStatic private external fun serializeViaJNI(any: Any, type: Type, out: Array<ByteArray?>): String?
@JvmStatic private external fun deserializeViaJNI(bytes: ByteArray, type: Type, out: Array<Any?>): String?
```

Update `JNIZBytesKotlin.kt`:
```kotlin
fun serialize(any: Any, kType: KType, out: Array<ByteArray?>): String? = serializeViaJNI(any, kType, out)
fun deserialize(bytes: ByteArray, kType: KType, out: Array<Any?>): String? = deserializeViaJNI(bytes, kType, out)
@JvmStatic private external fun serializeViaJNI(any: Any, kType: KType, out: Array<ByteArray?>): String?
@JvmStatic private external fun deserializeViaJNI(bytes: ByteArray, kType: KType, out: Array<Any?>): String?
```

Update zenoh-java callers:
- `ZSerializer.serialize()`: `val out = arrayOfNulls<ByteArray>(1); val err = JNIZBytes.serialize(t as Any, this.type, out); if (err != null) throw ZError(err); return ZBytes(out[0]!!)`
- `ZDeserializer.deserialize()`: `val out = arrayOfNulls<Any>(1); val err = JNIZBytes.deserialize(zbytes.bytes, this.type, out); if (err != null) throw ZError(err); return out[0]!! as T`
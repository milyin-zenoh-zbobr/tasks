Changes to `zenoh-jni/src/zenoh_id.rs`:
- `toStringViaJNI(zenoh_id, out: JObjectArray) -> jstring`: write string to out[0], return null on success

Changes to `zenoh-jni/src/logger.rs`:
- `startLogsViaJNI(filter) -> jstring`: no out, void-like, return null on success

Changes to `zenoh-jni/src/scouting.rs`:
- `scoutViaJNI(..., out: JLongArray) -> jstring`: write scout ptr to out[0]

Update `JNIZenohId.kt`:
```kotlin
fun toString(bytes: ByteArray, out: Array<String?>): String? = toStringViaJNI(bytes, out)
private external fun toStringViaJNI(bytes: ByteArray, out: Array<String?>): String?
```

Update `JNILogger.kt`:
```kotlin
fun startLogs(filter: String): String? = startLogsViaJNI(filter)
private external fun startLogsViaJNI(filter: String): String?
```

Update `JNIScout.kt`:
```kotlin
fun scout(..., out: Array<JNIScout?>): String? {
    val rawOut = LongArray(1)
    val err = scoutViaJNI(whatAmI, callback, onClose, config?.ptr ?: 0, rawOut)
    if (err == null) out[0] = JNIScout(rawOut[0])
    return err
}
private external fun scoutViaJNI(whatAmI: Int, callback: JNIScoutCallback, onClose: JNIOnCloseCallback, configPtr: Long, out: LongArray): String?
```

Update zenoh-java callers:
- `ZenohId.toString()`: `val out = arrayOfNulls<String>(1); val err = JNIZenohId.toString(bytes, out); if (err != null) throw ZError(err); return out[0]!!`
- `Logger.start()`: `val err = JNILogger.startLogs(filter); if (err != null) throw ZError(err)`
- `Zenoh.kt` scout methods: `val out = arrayOfNulls<JNIScout>(1); val err = JNIScout.scout(..., out); if (err != null) throw ZError(err); jniScout = out[0]!!`
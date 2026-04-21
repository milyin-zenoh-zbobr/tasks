Change all JNI functions in `zenoh-jni/src/config.rs` to return `jstring` (null=success, non-null=error) with typed `out` parameters. Add doc comments.

Changes per function:
- `loadDefaultConfigViaJNI(out: JLongArray) -> jstring`: write ptr to out[0], return null_mut()
- `loadConfigFileViaJNI(path, out: JLongArray) -> jstring`: write ptr to out[0] on success, return error jstring on failure
- `loadJsonConfigViaJNI(json, out: JLongArray) -> jstring`: same
- `loadYamlConfigViaJNI(yaml, out: JLongArray) -> jstring`: same
- `getJsonViaJNI(cfg_ptr, key, out: JObjectArray) -> jstring`: write json string to out[0] on success
- `insertJson5ViaJNI(cfg_ptr, key, value) -> jstring`: no out param (void-like), return null on success

Update `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIConfig.kt`:
```kotlin
companion object {
    fun loadDefault(out: Array<JNIConfig?>): String? {
        val rawOut = LongArray(1)
        val err = loadDefaultConfigViaJNI(rawOut)
        if (err == null) out[0] = JNIConfig(rawOut[0])
        return err
    }
    fun loadFromFile(path: String, out: Array<JNIConfig?>): String? { /* same pattern */ }
    fun loadFromJson(rawConfig: String, out: Array<JNIConfig?>): String? { /* same pattern */ }
    fun loadFromYaml(rawConfig: String, out: Array<JNIConfig?>): String? { /* same pattern */ }
    fun getJson(ptr: Long, key: String, out: Array<String?>): String? { ... }
    fun insertJson5(ptr: Long, key: String, value: String): String? { ... }
    
    private external fun loadDefaultConfigViaJNI(out: LongArray): String?
    private external fun loadConfigFileViaJNI(path: String, out: LongArray): String?
    private external fun loadJsonConfigViaJNI(rawConfig: String, out: LongArray): String?
    private external fun loadYamlConfigViaJNI(rawConfig: String, out: LongArray): String?
    private external fun getJsonViaJNI(ptr: Long, key: String, out: Array<String?>): String?
    private external fun insertJson5ViaJNI(ptr: Long, key: String, value: String): String?
    private external fun freePtrViaJNI(ptr: Long)
}
fun getJson(key: String, out: Array<String?>): String? = getJsonViaJNI(ptr, key, out)
fun insertJson5(key: String, value: String): String? = insertJson5ViaJNI(ptr, key, value)
```

Update `zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt`:
- All JNIConfig calls use new String? return pattern
- `loadDefault`: `val out = arrayOfNulls<JNIConfig>(1); val err = JNIConfig.loadDefault(out); if (err != null) throw ZError(err); return Config(out[0]!!)`
- `getJson`: `val out = arrayOfNulls<String>(1); val err = jniConfig.getJson(key, out); if (err != null) throw ZError(err); return out[0]!!`
- `insertJson5`: `val err = jniConfig.insertJson5(key, value); if (err != null) throw ZError(err)`
For each exported function in these files:
- Add `error_out: JObjectArray` as last parameter
- Change return type per convention (null/0L/0 for objects/longs/int sentinels)
- Replace throw_exception!(env, err) with set_error_string(&mut env, &error_out, &err.to_string()) + sentinel return

config.rs:
- loadConfigFileViaJNI: *const Config -> return null() on error
- loadJsonConfigViaJNI: same
- loadYamlConfigViaJNI: same
- getJsonViaJNI: jstring -> return null on error (JString::default().as_raw())
- insertJson5ViaJNI: return type Unit -> jint, return -1 on error, 0 on success
- getIdViaJNI (if exists in config.rs, check)
- loadDefaultConfigViaJNI: add error_out for API uniformity, doesn't actually fail

key_expr.rs:
- tryFromViaJNI: return null on error
- autocanonizeViaJNI: return null on error
- intersectsViaJNI: jboolean -> jint, return -1 on error
- includesViaJNI: jboolean -> jint, return -1 on error
- relationToViaJNI: return -1 on error

logger.rs:
- startLogsViaJNI: Unit -> jint, return -1 on error, 0 on success

zenoh_id.rs:
- toStringViaJNI: return null on error
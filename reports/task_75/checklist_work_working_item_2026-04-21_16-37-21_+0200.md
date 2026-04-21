Changes to `zenoh-jni/src/session.rs`:

1. REMOVE: `openSessionWithJsonConfigViaJNI` and `openSessionWithYamlConfigViaJNI` functions and their private helpers

2. Change each JNI export:
- `openSessionViaJNI(config_ptr, out: JLongArray) -> jstring`: write session ptr to out[0], return null on success
- `declarePublisherViaJNI(..., out: JLongArray) -> jstring`: write publisher ptr
- `putViaJNI(...) -> jstring`: no out, return null on success
- `deleteViaJNI(...) -> jstring`: no out, return null on success
- `declareSubscriberViaJNI(..., out: JLongArray) -> jstring`: write subscriber ptr
- `declareQuerierViaJNI(..., out: JLongArray) -> jstring`: write querier ptr
- `declareQueryableViaJNI(..., out: JLongArray) -> jstring`: write queryable ptr
- `declareKeyExprViaJNI(..., out: JLongArray) -> jstring`: write key_expr ptr
- `getViaJNI(...) -> jstring`: no out
- `getPeersZidViaJNI(session_ptr, out: JObjectArray) -> jstring`: write list to out[0]
- `getRoutersZidViaJNI(session_ptr, out: JObjectArray) -> jstring`: write list to out[0]
- `getZidViaJNI(session_ptr, out: JObjectArray) -> jstring`: write byte array to out[0]
- `declareAdvancedSubscriberViaJNI(..., out: JLongArray) -> jstring`: write ptr
- `declareAdvancedPublisherViaJNI(..., out: JLongArray) -> jstring`: write ptr

Update `JNISession.kt` to match new signatures:
- `open(config, out: Array<JNISession?>): String?` - bridge via LongArray
- All declare* methods: `fun declarePublisher(..., out: Array<JNIPublisher?>): String?`
- Void methods: `fun put(...): String?`, `fun get(...): String?`, `fun delete(...): String?`
- `getZid(out: Array<ByteArray?>): String?`
- `getPeersZid(out: Array<List<ByteArray>?>): String?`
- `getRoutersZid(out: Array<List<ByteArray>?>): String?`

Update zenoh-java `Session.kt` callers:
- Session.launch(): `val out = arrayOfNulls<JNISession>(1); val err = JNISession.open(config.jniConfig, out); if (err != null) throw ZError(err); jniSession = out[0]`
- declarePublisher: `val out = arrayOfNulls<JNIPublisher>(1); val err = jniSession.declarePublisher(..., out); if (err != null) throw ZError(err); jniPublisher = out[0]!!`
- put/delete/get: check `String?` return, throw ZError if non-null
- getZid: `val out = arrayOfNulls<ByteArray>(1); val err = jniSession.getZid(out); if (err != null) throw ZError(err); return ZenohId(out[0]!!)`
- getPeersZid/getRoutersZid: `val out = arrayOfNulls<List<ByteArray>>(1); val err = jniSession.getPeersZid(out); if (err != null) throw ZError(err); return out[0]!!.map { ZenohId(it) }`
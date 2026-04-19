Zenoh.kt (commonMain):
- Remove `internal expect object ZenohLoad` declaration at the bottom

Config.kt:
- JNIConfig.loadDefaultConfig() → JNIConfig.loadDefault()
- JNIConfig.loadConfigFile(path) → JNIConfig.loadFromFile(path.toString())
- JNIConfig.loadJsonConfig(s) → JNIConfig.loadFromJson(s)
- JNIConfig.loadJson5Config(s) → JNIConfig.loadFromJson(s) [no loadFromJson5 in runtime]
- All wrap in runCatching { Config(JNIConfig.loadXxx(...)) }

KeyExpr.kt:
- JNIKeyExpr.tryFrom(s) → runCatching { KeyExpr(JNIKeyExpr.tryFrom(s)) }
- JNIKeyExpr.autocanonize(s) → runCatching { KeyExpr(JNIKeyExpr.autocanonize(s)) }
- intersects: add jniKeyExpr + keyExpr primitives for both args
- includes: add jniKeyExpr + keyExpr primitives for both args
- relationTo: add primitives, wrap result with SetIntersectionLevel.fromInt(...)
- joinViaJNI → runCatching { KeyExpr(JNIKeyExpr.join(ke.jniKeyExpr, ke.keyExpr, other)) }
- concatViaJNI → runCatching { KeyExpr(JNIKeyExpr.concat(ke.jniKeyExpr, ke.keyExpr, other)) }

ZenohId.kt:
- JNIZenohId.toStringViaJNI(bytes) → JNIZenohId.toString(bytes)

Logger.kt:
- Remove private external fun startLogsViaJNI
- startLogsViaJNI(filter) → io.zenoh.jni.JNILogger.startLogs(filter)
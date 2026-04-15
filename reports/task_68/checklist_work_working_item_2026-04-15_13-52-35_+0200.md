Update zenoh-java facade classes:
- Config.kt: Preserve exact public API, update implementations to wrap Long: `Config(JNIConfig(JNIConfig.loadDefaultConfig()))`, etc. Also update class to `class Config internal constructor(internal val jniConfig: JNIConfig)`
- KeyExpr.kt: JNIKeyExpr.tryFrom() now returns String; update: `KeyExpr(JNIKeyExpr.tryFrom(keyExpr), null)`. Join/concat similarly wrap String.
- Publisher.kt: decompose IntoZBytes/Encoding → bytes and call primitive jniPublisher.put/delete
- Query.kt: decompose Sample/IntoZBytes/Encoding/KeyExpr → primitives and call public jniQuery wrapper methods

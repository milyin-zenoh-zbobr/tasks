Session.kt is the most complex file. Changes:
- jniSession field stays JNISession? (now resolves to runtime's version)
- Session init: JNISession() then jniSession!!.open(config) → JNISession.open(config.jniConfig)
- Each method that called zenoh-kotlin's JNI adapter (with domain objects) must be replaced with:
  1. Set up JNI callback lambdas inline (e.g., JNISubscriberCallback { ... → Sample(...) })
  2. Call runtime JNISession methods with explicit primitives
  3. Wrap returned JNI objects in domain wrappers
- Reference: zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt on common-jni branch
- Callback interfaces come from io.zenoh.jni.callbacks.* (runtime)
- Session close: jniSession?.close() → runtime's JNISession.close()
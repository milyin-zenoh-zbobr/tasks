JNILiveliness.kt:
- Remove 3 private external fun declarations (getViaJNI, declareTokenViaJNI, declareSubscriberViaJNI)
- Remove direct jniSession.sessionPtr.get() access (internal in runtime)
- Replace with calls to runtime's public JNISession methods:
  - declareTokenViaJNI → jniSession.declareLivelinessToken(keyExpr.jniKeyExpr, keyExpr.keyExpr)
  - declareSubscriberViaJNI → jniSession.declareLivelinessSubscriber(keyExpr.jniKeyExpr, keyExpr.keyExpr, subCallback, history, onClose)
  - getViaJNI → jniSession.livelinessGet(keyExpr.jniKeyExpr, keyExpr.keyExpr, getCallback, timeout.toMillis(), onClose)
- Update callback imports to runtime's io.zenoh.jni.callbacks.*
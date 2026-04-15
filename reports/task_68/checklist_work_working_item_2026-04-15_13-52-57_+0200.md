Update remaining facade files:
- Zenoh.kt: Scout methods build inline JNIScoutCallback, call JNIScout.scout(binaryWhatAmI, scoutCallback, onClose, configPtr), wrap Long in CallbackScout/HandlerScout
- Liveliness.kt: pass keyExpr as primitives (sessionPtr, keyExprPtr, keyExprStr) to runtime JNILiveliness; wrap returned Long in LivelinessToken(JNILivelinessToken(ptr))
- Querier.kt: performGet creates JNIGetCallback inline, calls jniQuerier.getViaJNI(ptr, keyExprPtr, keyExprStr, ...)

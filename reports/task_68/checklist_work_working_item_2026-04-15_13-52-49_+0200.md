Update Session.kt:
- Update launch() to call `JNISession.open(config.jniConfig.ptr)` instead of `JNISession.open(config)`
- Inline callback assembly from old JNISession into resolveSubscriberWithHandler/Callback, resolveQueryableWithHandler/Callback, resolveGetWithHandler/Callback methods in Session.kt
- Each method now directly creates JNISubscriberCallback/JNIQueryableCallback/JNIGetCallback inline and calls jniSession external funs directly
- Inline declarePublisher, declareQuerier, performGet, performPut, performDelete, declareKeyExpr, undeclareKeyExpr, zid/peersZid/routersZid

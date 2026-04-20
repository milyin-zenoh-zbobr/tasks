The plan has been submitted. Here's a summary of what was addressed in this revision compared to the prior plan (ctx_rec_5):

**Issues fixed from ctx_rec_6:**

1. **`Liveliness.kt` added to Phase 5** — This file calls `jniSession.declareLivelinessToken()`, `jniSession.livelinessGet()`, and `jniSession.declareLivelinessSubscriber()` directly (bypassing Session.kt), with 6 total call sites across 3 overloaded method groups. It was missing from the prior plan's call-site list.

2. **Object-returning runtime adapters explicitly specified as nullable** — Phase 4 now clearly states that all adapter methods constructing Kotlin JNI wrapper objects from Long pointers (JNIPublisher, JNISubscriber, JNILivelinessToken, JNIScout, etc.) must return nullable types and return `null` when the pointer is 0L. The same applies to `List<ByteArray>?` (getPeers/getRouters) and `Any?` (zbytes deserialize).
For all JNI call sites in zenoh-java, apply the error-array pattern:
- Session.kt: ~16 JNI call sites (session open, declare publisher/subscriber/querier/queryable/keyexpr/advancedPublisher/advancedSubscriber, put/delete/get, getPeers/getRouters/getZid)
- liveliness/Liveliness.kt: declareLivelinessToken, livelinessGet, declareLivelinessSubscriber
- Zenoh.kt: JNIScout.scout() call site and session open calls
- Config.kt: config loading call sites
- keyexpr/KeyExpr.kt: tryFrom, autocanonize, intersects, includes, relationTo, join, concat
- pubsub/Publisher.kt: put, delete
- query/Query.kt: replySuccess, replyError, replyDelete
- query/Querier.kt: get
- config/ZenohId.kt: toString
- Logger.kt: startLogs
- jvmAndAndroidMain/kotlin/io/zenoh/ext/ZDeserializer.kt: JNIZBytes.deserialize()
- jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerializer.kt: JNIZBytes.serialize()

Pattern for Long/pointer-returning:
val error = arrayOfNulls<String>(1)
val ptr = jniXxx.someMethod(params, error)
if (ptr == 0L) throw ZError(error[0] ?: "Unknown error in X")

Pattern for Int-returning (error indicator < 0):
val error = arrayOfNulls<String>(1)
val result = jniXxx.someMethod(params, error)
if (result < 0) throw ZError(error[0] ?: "Unknown error in X")

Keep @Throws(ZError::class) on public API methods in zenoh-java.
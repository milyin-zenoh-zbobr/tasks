Create remaining JNI adapters in zenoh-jni-runtime:
- JNIPublisher: `public class JNIPublisher(public val ptr: Long)` with primitive put/delete wrappers, no facade imports
- JNIQuery: `public class JNIQuery(private val ptr: Long)` with PUBLIC primitive wrappers (replySuccess, replyError, replyDelete, close), no facade imports
- JNIQuerier: `public class JNIQuerier(val ptr: Long)` with public getViaJNI wrapper, no facade imports
- JNIScout: companion WITHOUT @JvmStatic on scoutViaJNI (preserves _00024Companion_ JNI symbol), public scout() method, no facade imports
- JNILiveliness: `public object JNILiveliness` with primitive API returning Long, no facade imports

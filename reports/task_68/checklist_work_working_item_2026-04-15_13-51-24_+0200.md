Create JNIConfig and JNIKeyExpr in zenoh-jni-runtime with public ptr:
- JNIConfig: `public class JNIConfig(public val ptr: Long)` with companion factory methods returning Long (not Config), preserve companion-without-JvmStatic (Rust uses _00024Companion_ prefix)
- JNIKeyExpr: `public class JNIKeyExpr(public val ptr: Long)` with companion factory methods returning String (not KeyExpr), same JNI symbol preservation
Both remove all io.zenoh.* facade imports.

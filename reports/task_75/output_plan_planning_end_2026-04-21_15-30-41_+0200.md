The plan is complete and submitted. Here's a summary of what it addresses:

**Root cause of the previous rejection (ctx_rec_5):** The prior plan incorrectly placed exception throwing inside `zenoh-jni-runtime`, which (a) violates the task requirement and (b) is impossible since `ZError` lives in `zenoh-java` which depends on runtime — not the other way around.

**The corrected three-layer design:**
1. **Rust JNI** (`zenoh-jni`): returns `jstring` (null=success, non-null=error message) + writes real value to a typed `out` parameter.
2. **`zenoh-jni-runtime`**: thin Kotlin passthrough — external declarations and public methods use `(…, out: OutType): String?` — no exceptions, no `ZError`.
3. **`zenoh-java`**: the only layer that calls `?.let { throw ZError(it) }` to convert error strings into exceptions.

All previously missing surfaces are included: `JNIZBytes.kt`, `JNIZBytesKotlin.kt`, `ZSerializer.kt`, `ZDeserializer.kt`, plus doc-comment restoration for 11 Rust files.
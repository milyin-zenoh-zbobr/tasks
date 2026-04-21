The plan is complete and ready for review. Here's a summary of what it covers:

**Two main tasks:**

1. **Restore Rust `///` doc comment blocks** that were accidentally removed across 14 Rust source files, updating the exception-throwing language to reflect the new error-string-return behavior.

2. **Change the uniform JNI API** from `(..params.., error: Array<String?>): T?` to `(..params.., out: TypedOut): String?` across all three layers:
   - **Rust** (`zenoh-jni`): returns `jstring` (null=success), writes to `JLongArray` (pointers) or `JObjectArray` (objects), nothing for void ops
   - **Runtime private externals** (`zenoh-jni-runtime`): match Rust ABI with `LongArray`/`Array<X?>` out params
   - **Runtime public API**: bridges `LongArray` → typed `JNISession?`, `JNIConfig?` etc. — wrapper-object construction stays in the runtime
   - **`zenoh-java`**: allocates typed out arrays, checks `String?` return, throws `ZError` — the only exception-throwing layer
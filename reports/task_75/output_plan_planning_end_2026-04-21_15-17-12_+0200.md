The plan is complete and submitted. Here's a summary of what it covers:

**Key additions vs. the previous plan (addressing ctx_rec_3 feedback):**

1. **Missing zbytes surface included** — `JNIZBytes.kt`, `JNIZBytesKotlin.kt` (runtime) and `ZSerializer.kt`, `ZDeserializer.kt` (zenoh-java) are now explicitly part of the plan with concrete new signatures.

2. **Out-parameter type mapping table** — explicit mapping from Kotlin return types to Rust JNI types (`JLongArray`, `JIntArray`, `JObjectArray`), grounded in the existing JNI conventions in the codebase.

3. **Uniform contract enforced across all surfaces** — both commonMain (session/config/query) and jvmAndAndroidMain (zbytes serialization) follow the same `String?` return + typed `out` param convention.

**Three-part work scope:**
- Part 1: Restore accidentally removed Rust `///` doc blocks
- Parts 2-4: Convert all Rust JNI + Kotlin runtime declarations to the new API
- Part 5: Simplify `zenoh-java` wrappers (drop error-array boilerplate)
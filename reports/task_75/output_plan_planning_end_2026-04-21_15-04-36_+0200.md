The plan is ready. Here's the summary of what was designed:

**Two tasks to implement:**

**1. Restore removed doc comments** — The work branch accidentally deleted `///` doc blocks from 11 Rust files (`config.rs`, `key_expr.rs`, `session.rs`, `publisher.rs`, `querier.rs`, `query.rs`, `logger.rs`, `scouting.rs`, `zenoh_id.rs`, `ext/advanced_publisher.rs`, `ext/advanced_subscriber.rs`). These need to be restored (with text updated to reflect the new API — no more "throws exception" wording).

**2. Uniform `String?` return API** — Every JNI native function is changed to:
- Return `String?` (`jstring` in Rust): null = success, non-null = error message
- Accept a typed `out` array as the last parameter to receive the real return value

The `out` parameter type depends on what the function currently returns:
- Pointers/Long → `LongArray` (Kotlin) / `JLongArray` (Rust)
- Int bool/ordinal → `IntArray` / `JIntArray`
- String? → `Array<String?>` / `JObjectArray`
- ByteArray? / List<ByteArray>? → `Array<...?>` / `JObjectArray`
- Pure success/fail functions → no `out` param at all

Changes span 15 Rust files, all `JNI*.kt` runtime files in `zenoh-jni-runtime`, and all zenoh-java wrapper Kotlin files that call into the JNI layer.
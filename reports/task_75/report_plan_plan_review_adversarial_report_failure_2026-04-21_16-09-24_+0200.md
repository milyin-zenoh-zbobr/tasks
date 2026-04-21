The plan is close, but it still has a blocking surface-coverage gap and one scope inconsistency.

1. **Blocking omission: `JNIPublisher` is missing from the runtime API map.**
   - The plan’s `zenoh-jni-runtime` public API section lists `JNIConfig`, `JNISession`, `JNIKeyExpr`, `JNIQuerier`, `JNIQuery`, `JNIAdvancedPublisher`, `JNIAdvancedSubscriber`, `JNIScout`, `JNIZBytes`, etc., but it does **not** include `JNIPublisher`.
   - That omission is architectural, not cosmetic: `zenoh-java` uses `JNIPublisher` directly in `zenoh-java/src/commonMain/kotlin/io/zenoh/pubsub/Publisher.kt` for both `put` and `delete`, and `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIPublisher.kt` still exposes the old `error: Array<String?>` + `Int` return contract.
   - A worker following the current plan could update session-level put/delete and still leave publisher-level put/delete on the old ABI, which would leave the migration incomplete.
   - The revision should explicitly add the full `JNIPublisher` chain:
     - `zenoh-jni/src/publisher.rs`
     - `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIPublisher.kt`
     - `zenoh-java/src/commonMain/kotlin/io/zenoh/pubsub/Publisher.kt`
     - Contract should match the corrected design: return `String?`, no typed return value, no `error` array, no throwing from runtime.

2. **Scope inconsistency: the plan says “all JNI export functions must return `jstring`”, but it omits exported session entry points that still return pointers.**
   - `zenoh-jni/src/session.rs` still exports `openSessionWithJsonConfigViaJNI` and `openSessionWithYamlConfigViaJNI`, both returning `*const Session` and taking `error_out`.
   - Those functions are not declared in `zenoh-jni-runtime`, so they are likely dead or legacy exports, but the plan does not say whether they should be:
     1. migrated to the new ABI,
     2. removed, or
     3. explicitly excluded from the migration.
   - This matters because the plan’s verification step currently says grepping for `-> *const` / `-> jint` / `-> jlong` in `ViaJNI` functions should come up empty, which is incompatible with leaving those exports untouched.
   - The revision should make an explicit architectural decision here. If these exports are unsupported legacy entry points, say so and exclude/remove them; otherwise include them in the migration surface.

Because of item 1, the plan is not yet safe to implement as-is. After adding `JNIPublisher` explicitly and resolving the exported-session-entry-point scope, the plan should be ready.
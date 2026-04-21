I reviewed `ctx_rec_12` against the current worktree and the relevant runtime/native/public call sites. The plan is now sound and ready for implementation.

Why this is implementation-ready:

1. **The affected runtime JNI surface is now fully covered.**
   I checked the actual `zenoh-jni-runtime` wrappers that still use the old `error: Array<String?>` pattern. The revised plan accounts for the full set of affected classes:
   - `JNIConfig`
   - `JNISession`
   - `JNIPublisher`
   - `JNIKeyExpr`
   - `JNIZenohId`
   - `JNILogger`
   - `JNIQuerier`
   - `JNIQuery`
   - `JNIAdvancedPublisher`
   - `JNIAdvancedSubscriber`
   - `JNIScout`
   - `JNIZBytes`
   - `JNIZBytesKotlin`

   That matches the codebase. The previous publisher omission has been fixed.

2. **The plan’s layering is now correct.**
   The current tree confirms that `zenoh-java` owns `ZError`, while `zenoh-jni-runtime` does not import or throw it. The revised plan preserves that boundary:
   - Rust returns `String?` error messages
   - runtime exposes `String?` and typed `out` parameters without throwing
   - `zenoh-java` converts non-null errors into `ZError`

   That is consistent with the task’s stated architecture and with how the modules are currently separated.

3. **The scalar-return contract is explicitly handled where it matters.**
   The codebase still has old scalar JNI APIs such as `JNIKeyExpr.intersects/includes/relationTo` and `JNIAdvancedPublisher.getMatchingStatus`. The revised plan correctly moves these to `String?` + `IntArray out`, which closes a real ABI gap that earlier versions of the plan left open.

4. **The `zenoh-java` caller list is materially correct.**
   I checked the public Kotlin layer and the listed files correspond to the real call sites that currently translate native failures into `ZError`, including:
   - `Config.kt`
   - `Session.kt`
   - `Zenoh.kt`
   - `Logger.kt`
   - `keyexpr/KeyExpr.kt`
   - `pubsub/Publisher.kt`
   - `query/Querier.kt`
   - `query/Query.kt`
   - `liveliness/Liveliness.kt`
   - `config/ZenohId.kt`
   - `jvmAndAndroidMain/.../ZSerializer.kt`
   - `jvmAndAndroidMain/.../ZDeserializer.kt`

   I did not find an additional affected public API file that would block implementation.

5. **The JVM/Android zbytes surface is covered.**
   `JNIZBytes` and `JNIZBytesKotlin` are both real affected runtime entry points. The plan includes them, which is necessary for the migration to be complete.

6. **The legacy session export decision is now coherent.**
   `zenoh-jni/src/session.rs` still exports `openSessionWithJsonConfigViaJNI` and `openSessionWithYamlConfigViaJNI`, but `zenoh-jni-runtime` does not bind them anywhere. The plan now makes an explicit decision to remove them, which resolves the earlier scope inconsistency with the verification step.

7. **The doc-restore portion is pointed at the right area.**
   I checked the branch diff against `origin/common-jni`. The removed `///` blocks are concentrated in the Rust JNI files the plan is targeting (for example `config.rs`, `session.rs`, `publisher.rs`, `key_expr.rs`, `query.rs`, `querier.rs`, `logger.rs`, `zbytes*.rs`, `advanced_*`, etc.). The omitted Rust files such as `subscriber.rs`, `queryable.rs`, `ext/matching_listener.rs`, and `ext/sample_miss_listener.rs` are free/close helpers and do not appear to be part of the removed-doc regression or the error-return ABI migration.

Non-blocking note:
- During implementation, the worker should keep the scope distinction clear between ABI-bearing JNI functions and free/close helpers. The plan already implies this correctly; I’m only calling it out so the worker does not waste time rewriting no-error cleanup exports unnecessarily.

Conclusion: the revised plan matches the current code structure, closes the previously missing JNI surfaces, and gives a clear enough direction for implementation without pushing the worker into the wrong architecture.
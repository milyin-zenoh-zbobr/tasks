I reviewed the revised plan in ctx_rec_7 against the current `common-jni` codebase and it is now sound enough to implement.

What I verified:
- The Rust exception surface matches the plan’s scope. Current `throw_exception!` call sites are in the files the plan names: `session.rs`, `config.rs`, `key_expr.rs`, `publisher.rs`, `query.rs`, `querier.rs`, `scouting.rs`, `logger.rs`, `zenoh_id.rs`, `zbytes.rs`, `zbytes_kotlin.rs`, `ext/advanced_publisher.rs`, `ext/advanced_subscriber.rs`, plus the async `load_on_close` path in `utils.rs`.
- The zenoh-jni-runtime side really does expose `ZError` today and throws from wrapper methods via `@Throws(ZError::class)`, so removing that export and switching to `error: Array<String?>` + sentinels is consistent with the existing layering.
- The previously missing zenoh-java liveliness consumer is now explicitly covered. `zenoh-java/src/commonMain/kotlin/io/zenoh/liveliness/Liveliness.kt` directly calls `JNISession.declareLivelinessToken`, `livelinessGet`, and `declareLivelinessSubscriber`, so adding it to the plan was required and now fixes the last architectural hole.
- The broadened Phase 4 guidance about nullable object-returning runtime wrappers matches the actual runtime API shape. Methods like `JNISession.open`, `JNIConfig.loadFromFile`, `JNIScout.scout`, `JNISession.declarePublisher`, `declareSubscriber`, etc. currently construct wrapper objects immediately from native pointers, so converting those wrappers to nullable-on-0L is the right runtime-level pattern once Rust stops throwing.
- The listed zenoh-java call-site set covers the actual direct consumers I found: `Session.kt`, `Zenoh.kt`, `Config.kt`, `KeyExpr.kt`, `Logger.kt`, `config/ZenohId.kt`, `liveliness/Liveliness.kt`, `jvmAndAndroidMain/.../ZSerializer.kt`, and `ZDeserializer.kt`. I did not find separate zenoh-java advanced extension API files at the moment, so the plan’s conditional wording there is acceptable and not a blocker.

Why I consider it implementation-ready:
- The boundary shift is clear: Rust/runtime stop throwing, runtime exposes raw nullable/sentinel results, zenoh-java recreates and throws `io.zenoh.exceptions.ZError`.
- The sentinel conventions are concrete enough to drive consistent Rust and Kotlin signature changes.
- The plan now covers both the exported JNI surface and the public zenoh-java layer that must preserve current behavior.

Minor non-blocking observations:
- Some runtime tests and comments will likely need mechanical updates because they currently assume exception-throwing JNI wrappers, especially around `JNIZBytes` / `JNIZBytesKotlin` and Rust doc comments that still say exceptions are thrown.
- `JNIConfig.insertJson5ViaJNI` has a pre-existing wrapper/signature oddity today, but the plan’s proposed normalization to an integer sentinel is still directionally correct and not an architectural issue.

Conclusion: the plan is ready for implementation.
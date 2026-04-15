I reviewed the plan from `ctx_rec_9` against the current branch and codebase. The plan is sound and ready for implementation.

Why it holds up against the repository:

1. The core architectural split is consistent with the current code.
   - Today `zenoh-java` mixes high-level facade assembly with low-level JNI adapters, especially in `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`, `JNIQuerier.kt`, `JNILiveliness.kt`, `JNIQuery.kt`, `JNIConfig.kt`, and `JNIKeyExpr.kt`.
   - The plan’s move to a primitive-only runtime module plus keeping object assembly in facade classes (`Session.kt`, `Query.kt`, `Publisher.kt`, `Querier.kt`, `Liveliness.kt`, `Zenoh.kt`, `Config.kt`, `KeyExpr.kt`) matches the codebase’s boundaries and does not fight existing conventions.

2. The plan correctly identifies the JNI symbol-shape constraints that are easy to get wrong.
   - `JNIConfig` and `JNIKeyExpr` really do rely on companion-object JNI symbols with `_00024Companion_` in Rust (`zenoh-jni/src/config.rs`, `zenoh-jni/src/key_expr.rs`), so preserving companion methods without `@JvmStatic` is important.
   - `JNISession.openSessionViaJNI` really is bound without the Companion infix today because the Kotlin side uses `@JvmStatic` (`zenoh-jni/src/session.rs` plus `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`).
   - `JNIScout` likewise depends on the companion-form symbol (`zenoh-jni/src/scouting.rs`), so the plan is right to preserve that pattern.
   - The stated `JNIPublisher` pattern is real and is the correct analog for the new runtime adapters (`zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNIPublisher.kt`).

3. The previously identified blockers are genuinely resolved in the revised plan.
   - `JNIConfig.ptr` and `JNIKeyExpr.ptr` are currently `internal`, and `Session.kt` / `JNISession.kt` / `KeyExpr.kt` really do depend on cross-type pointer access. Making them public in a separate module is necessary.
   - `JNIQuery` currently keeps `ptr` private and exposes facade-typed methods; the plan’s wrapper-method approach is the right way to avoid leaking `ptr` while still making the runtime reusable.
   - `Config.kt`’s public API today is `loadDefault`, `fromFile(File)`, `fromFile(Path)`, `fromJson`, `fromJson5`, `fromYaml`; preserving those names exactly is the correct requirement.
   - `Session.launch()` currently calls `JNISession.open(config)`, so the plan’s explicit one-line adaptation to `config.jniConfig.ptr` is correct.

4. The advanced pub/sub part of the plan is grounded in the branch state.
   - The Rust exports for `JNIAdvancedPublisher`, `JNIAdvancedSubscriber`, `JNIMatchingListener`, and `JNISampleMissListener` do exist in `zenoh-jni/src/ext/*` and `zenoh-jni/src/session.rs`.
   - The Kotlin side for those adapters does not exist yet in this repo, so adding them in the runtime module is the right place.

5. The special-case exclusions are correct.
   - `JNIZBytes` should stay in `zenoh-java`; it is facade-aware and not primitive-only.
   - `Logger.kt` must stay in `zenoh-java` because the Rust symbol is bound to `io.zenoh.Logger`, not `io.zenoh.jni.*` (`zenoh-jni/src/logger.rs`).
   - The explicit `ZenohLoad` call in `Logger.start()` is a good and necessary safeguard because direct logger use should not rely on callers having touched `Zenoh` first.

Minor non-blocking implementation cautions:

1. Publishing/release wiring needs care because this repo currently publishes via aggregate root tasks in GitHub Actions (`publish-jvm.yml`, `publish-android.yml`) and publishes Dokka output only from `zenoh-java`. Adding a second published subproject is compatible with the plan, but the worker should make sure the new module’s publication setup does not accidentally diverge from the existing release flow.

2. The verification grep in the plan is slightly too strict as written: `zenoh-jni-runtime` is expected to import `io.zenoh.ZenohLoad` and `io.zenoh.Target`, so the check should be interpreted as “no facade imports beyond the runtime-owned loader/target types.” This is only a wording issue in verification, not an architectural problem.

Overall verdict: the plan is coherent, consistent with the existing codebase, and specific enough for implementation without sending the worker in the wrong direction.
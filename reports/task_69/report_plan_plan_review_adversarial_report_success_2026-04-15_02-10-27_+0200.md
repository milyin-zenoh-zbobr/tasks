I reviewed `ctx_rec_3` against the local zenoh-kotlin codebase and the required zenoh-java branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`. The plan is sound and ready for implementation.

Why this plan is correct:

1. It fixes the main architectural mistake from the earlier proposal.
   zenoh-kotlin and zenoh-java both publish overlapping public classes in `io.zenoh.*` (`Session`, `Config`, `KeyExpr`, `Reply`, etc.). Depending on zenoh-java’s public artifact directly would create classpath/FQCN collisions. The reviewed plan correctly avoids that by placing the reusable layer under a separate runtime artifact with a distinct package boundary (`io.zenoh.jni.*`).

2. It matches the real API differences between the two facades.
   The local zenoh-kotlin API is Result-based (`Config.fromFile(): Result<Config>`, `KeyExpr.tryFrom(): Result<KeyExpr>`, `Reply` as `Result<Sample>`), while the zenoh-java branch is exception-based (`Config.loadDefault()`, `KeyExpr.tryFrom()` throwing, sealed `Reply.Success` / `Reply.Error`). Because those public semantics differ, the shared layer cannot expose facade objects. The plan correctly requires the runtime module to expose only primitives / handles / raw byte arrays and leaves object assembly in each facade.

3. It covers the JNI surface broadly enough.
   The local repo shows JNI is not limited to Session/pubsub/query. JNI also appears in scouting (`Zenoh.kt` + `JNIScout.kt`), logger startup (`Logger.kt`), key expression/config helpers, serialization helpers, liveliness, and advanced pub/sub. The plan explicitly accounts for those surfaces and does not leave the worker with a partial migration that would rediscover hidden JNI coupling late.

4. It is consistent with the zenoh-java branch layout.
   The target zenoh-java branch already has the expected split between a public `zenoh-java` module and a root `zenoh-jni` native crate, plus an internal `io.zenoh.jni.*` layer in the public module. Extracting that JNI layer into a separate published subproject is a natural extension of the current structure rather than a foreign architecture.

Non-blocking suggestions for implementation:

1. Treat native packaging/loading as part of the runtime artifact contract.
   The worker should ensure `ZenohLoad` and native-resource packaging move fully into the new runtime artifact so zenoh-kotlin has no remaining `System.loadLibrary`, target-detection, or native-resource wiring. That is already implied by the plan and should remain a hard implementation rule.

2. Do not over-share model types prematurely.
   The plan is right to keep `Config`, `KeyExpr`, and `Reply` facade-specific. The worker should apply the same caution to any type that embeds lifecycle, error semantics, or declaration ownership, even if it looks structurally similar at first glance.

3. The exact filesystem placement of the Rust crate is secondary.
   The architectural requirement is that zenoh-java owns the native crate and the published runtime artifact. Whether the Rust crate is physically moved under the new subproject or kept at repo root and consumed from there is an implementation detail; it should be chosen for the least disruptive build/publishing setup.

Bottom line: this plan chooses the correct reuse boundary, preserves zenoh-kotlin’s API contract, and identifies the necessary zenoh-java-side refactoring to make zenoh-kotlin truly JNI-free. It is implementation-ready.
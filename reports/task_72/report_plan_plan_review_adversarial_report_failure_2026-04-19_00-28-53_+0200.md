I reviewed the revised plan against this repository and the upstream `eclipse-zenoh/zenoh-java` `common-jni` branch. I do **not** see evidence that `zenoh-jni-runtime` is insufficient overall; it appears to cover the required native surface, including session, pub/sub, queries, liveliness, scouting, logging, and Kotlin-aware serialization. However, the plan is still **not implementation-ready** for two architectural reasons.

## 1. The plan still misses a duplicate public-class conflict outside `io.zenoh.jni.*`

The plan now handles the `ZenohLoad` collision, but it still assumes the only class-name overlap to resolve is the JNI package. That is false.

Both codebases define the same public class:
- local: `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`
- upstream runtime: `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`

Both are `io.zenoh.exceptions.ZError` with the same shape. If zenoh-kotlin depends on `zenoh-jni-runtime` without explicitly addressing this, the final classpath/publication will contain duplicate definitions of the same FQCN. That is a real packaging/runtime problem, not a cosmetic issue.

### Why this blocks the plan

A worker following the current plan is told to delete the local JNI package and use the runtime types directly, but nothing tells them to resolve this additional duplicate class. That means the plan is still incomplete at the module-boundary level.

### What the plan should say

It should explicitly add a compatibility/duplication rule such as:
- delete `zenoh-kotlin`’s local `io.zenoh.exceptions.ZError` and rely on the runtime’s identical `io.zenoh.exceptions.ZError`, preserving the public API FQCN, or
- otherwise ensure only one definition is packaged/published.

Without that, the migration is underspecified and likely to produce duplicate classes.

## 2. `AdvancedSubscriber.kt` is not import-only; it is another real adaptation hotspot

The plan’s Phase 3e says `AdvancedSubscriber.kt` is “drop-in compatible” and needs only an import update because it supposedly only calls `.close()`. That is incorrect for this repository.

Current `AdvancedSubscriber.kt` actively uses higher-level helper methods from zenoh-kotlin’s local `JNIAdvancedSubscriber`:
- `declareDetectPublishersSubscriber(...)`
- `declareBackgroundDetectPublishersSubscriber(...)`
- `declareSampleMissListener(...)`
- `declareBackgroundSampleMissListener(...)`

Those helpers are not just raw JNI calls; the local adapter constructs `Sample`, `SampleMiss`, `Subscriber`, and `SampleMissListener` domain objects and wraps results.

Upstream runtime `JNIAdvancedSubscriber` has similarly named methods, but with different signatures and responsibilities: it expects JNI callback interfaces directly and returns runtime JNI objects / throws, not zenoh-kotlin domain wrappers and `Result<T>`.

### Why this blocks the plan

A worker following the current plan will be misled into treating `AdvancedSubscriber.kt` as a trivial import swap, when in reality it needs the same kind of adaptation the plan already acknowledges for `AdvancedPublisher.kt`, `Publisher.kt`, `KeyExpr.kt`, `Config.kt`, and `JNILiveliness.kt`.

### What the plan should say

It should explicitly mark `AdvancedSubscriber.kt` as a real adaptation point, with one of these strategies:
1. keep a thin zenoh-kotlin adapter around runtime `JNIAdvancedSubscriber`, or
2. rewrite `AdvancedSubscriber.kt` to inline the callback/domain-object conversion against runtime `JNIAdvancedSubscriber`.

As written, the plan is directionally wrong on this file.

## Bottom line

`zenoh-jni-runtime` still appears sufficient overall, so this is **not** a failure of the runtime itself. But the plan remains **not ready for implementation** because:
1. it still misses a duplicate-class conflict (`io.zenoh.exceptions.ZError`), and
2. it still understates the migration work for `AdvancedSubscriber.kt`.

Once those are corrected, the plan should be much closer to implementation-ready.

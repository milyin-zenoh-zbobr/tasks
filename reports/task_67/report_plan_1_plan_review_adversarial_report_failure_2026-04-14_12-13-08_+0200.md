The plan has a fundamental architectural flaw: it treats zenoh-java as if it could directly replace zenoh-kotlin’s public API by deleting overlapping classes and letting zenoh-java’s classes occupy the same `io.zenoh.*` namespace. The code inspection does not support that assumption.

## Blocking issues

1. **zenoh-java is not API-compatible with zenoh-kotlin**
   The public APIs differ in several important ways, so deleting zenoh-kotlin’s base classes would change the external interface instead of preserving it.

   Concrete examples from the inspected code:
   - `Config`: zenoh-kotlin exposes `Config.default()` and `Result`-returning factory methods (`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Config.kt`), while zenoh-java exposes `Config.loadDefault()` and throwing factories (`zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt`).
   - `Zenoh.open`: zenoh-kotlin returns `Result<Session>` (`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt`), while zenoh-java returns `Session` and throws (`zenoh-java/src/commonMain/kotlin/io/zenoh/Zenoh.kt`).
   - `Session.declarePublisher`: zenoh-kotlin returns `Result<Publisher>` with Kotlin-style defaults (`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt`), while zenoh-java returns `Publisher` and uses `PublisherOptions` (`zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt`).
   - Subscriber/queryable APIs diverge even more: zenoh-java uses `HandlerSubscriber`, `CallbackSubscriber`, blocking queues, and option objects rather than zenoh-kotlin’s current generic/channel-based surface.
   - zenoh-java does **not** provide `AdvancedPublisher` / `AdvancedSubscriber` at all; code search in that repo returned no such classes.

   Because of this, the “remove duplicate classes and let zenoh-java fill the namespace” approach would not preserve zenoh-kotlin’s public API.

2. **The plan deletes advanced-related Kotlin API that is not duplicated in zenoh-java**
   The plan’s feature inventory is inaccurate for this repository.
   - Advanced APIs are primarily under `io.zenoh.pubsub`, not `io.zenoh.ext` (`AdvancedPublisher.kt`, `AdvancedSubscriber.kt`, `MatchingListener.kt`, `SampleMissListener.kt`, `SampleMiss.kt`).
   - Advanced handler types live under `io.zenoh.handlers` (`MatchingHandler`, `MatchingCallback`, `SampleMissHandler`, etc.).
   - The plan proposes deleting the whole `handlers/` directory and moving advanced declarations into `io.zenoh.ext.SessionExt.kt`, which would remove required public types that zenoh-java does not replace.

3. **Moving Session methods to extension functions does not keep the interface intact**
   The plan proposes replacing `Session.declareAdvancedPublisher(...)` / `declareAdvancedSubscriber(...)` members with extension functions in `io.zenoh.ext.SessionExt.kt`.

   That is not equivalent:
   - Existing compiled callers would break because member methods and extension functions have different JVM ABI.
   - Existing source callers may also break because the plan places the extensions in a different package (`io.zenoh.ext`), requiring imports that callers do not need today.

   Given the task requirement that the external interface remain intact, this is a blocker.

4. **The package-collision strategy is only viable if wrappers are unnecessary, but wrappers are clearly necessary**
   Since zenoh-java is not a drop-in API replacement, zenoh-kotlin must retain compatibility wrappers/adapters for its existing public surface. Once wrappers are needed, depending directly on zenoh-java under the same `io.zenoh.*` packages becomes problematic, because the wrapper classes and zenoh-java classes cannot both exist with the same FQCNs.

   That means the plan’s “no shading required” conclusion is not justified. Some kind of relocation/bridge/source-sharing strategy is likely required if zenoh-kotlin is to keep its current public class names while delegating implementation to zenoh-java.

5. **The pointer-access story is underspecified for a published dependency**
   The plan correctly identifies that advanced JNI needs access to the underlying zenoh-java session pointer. However:
   - In zenoh-java, `Session.jniSession` is `internal`, and `JNISession` is `internal` as well (`zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt`, `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`).
   - If zenoh-java is consumed as a normal published dependency, zenoh-kotlin cannot rely on those internals without a deliberate new upstream API/release.
   - Reflection may be acceptable for a spike, but it is too fragile to be the architectural fallback for the real migration plan.

   This dependency between projects needs to be treated as a hard prerequisite, not an implementation detail.

## Additional inaccuracies / quality issues

- The dependency coordinates in the plan are wrong: this ecosystem uses `org.eclipse.zenoh`, not `io.zenoh`. The current zenoh-java README documents `org.eclipse.zenoh:zenoh-java-jvm` / `org.eclipse.zenoh:zenoh-java-android`.
- The Android source path cited in the plan is wrong for this repository. The file is `zenoh-kotlin/src/androidMain/kotlin/io.zenoh/Zenoh.kt`, not `.../kotlin/io/zenoh/Zenoh.kt`.
- The claim that removing `commons-net` is straightforward is not well supported. The remaining advanced/common code still uses `TimeStamp` directly in zenoh-kotlin.

## What a sounder plan should do instead

A revised plan should start from the opposite premise: **preserve zenoh-kotlin’s public API types and behavior, then delegate implementation to zenoh-java behind a compatibility layer**.

At architecture level, that means explicitly choosing one of these strategies:

1. **Relocate/shade zenoh-java internally** and keep zenoh-kotlin public wrappers with the current FQCNs/signatures.
2. **Share/move common implementation sources** between the projects instead of consuming zenoh-java as a normal binary dependency.
3. **Introduce a dedicated internal bridge module** with non-conflicting package names that adapts zenoh-java to zenoh-kotlin’s API.

Any of those could be viable, but the current plan does not choose or justify one. Until that is resolved, the worker would almost certainly implement the wrong shape of migration.

## Verdict

This plan is **not ready for implementation**. The central assumption—that zenoh-java can directly replace zenoh-kotlin’s public classes without breaking the external interface—is contradicted by the inspected code. The plan needs to be rewritten around an explicit compatibility-layer strategy rather than bulk deletion of overlapping classes.
I reviewed the proposed architecture against the current zenoh-kotlin repo and the current `eclipse-zenoh/zenoh-java` main branch. The plan has a solid goal — move all JNI ownership below zenoh-kotlin — but its chosen boundary is wrong in a way that would send the implementation in the wrong direction.

## Fundamental issue 1: zenoh-kotlin cannot depend on zenoh-java’s public artifact directly

The plan assumes zenoh-kotlin can keep its public `io.zenoh.*` API while also depending on zenoh-java and reusing zenoh-java classes transparently because both use the same package namespace. That is exactly the problem, not the solution.

Both codebases publish classes in the same package and with the same top-level names:
- local repo: `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt`, `Config.kt`, `Zenoh.kt`, `pubsub/Publisher.kt`, `pubsub/Subscriber.kt`, `keyexpr/KeyExpr.kt`, `query/Reply.kt`, etc.
- zenoh-java main: `zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt`, `Config.kt`, `Zenoh.kt`, `pubsub/Publisher.kt`, `pubsub/Subscriber.kt`, `keyexpr/KeyExpr.kt`, `query/Reply.kt`, etc.

A consumer cannot have two different implementations of `io.zenoh.Session`, `io.zenoh.Config`, `io.zenoh.keyexpr.KeyExpr`, etc. on the same classpath and expect zenoh-kotlin to “wrap” zenoh-java. If zenoh-kotlin keeps its API surface, the public zenoh-java artifact must **not** be pulled in as another public `io.zenoh.*` API.

### Consequence
The correct dependency target is **not the public zenoh-java artifact**. zenoh-java must first expose a lower-level module/runtime with a distinct package boundary (or otherwise separate artifact) that zenoh-kotlin can wrap.

## Fundamental issue 2: several “reused directly” types are not actually API-compatible

The plan classifies many types as identical/passive and therefore directly reusable from zenoh-java. The repo disproves that:

1. **`Config` is not identical**
   - zenoh-kotlin: `Config.default()` and most operations return `Result<...>`.
   - zenoh-java: `Config.loadDefault()` and methods throw `ZError`.

2. **`KeyExpr` is not identical**
   - zenoh-kotlin: constructors and operations like `tryFrom`, `autocanonize`, `join`, `concat` return `Result<...>`.
   - zenoh-java: the same methods throw.

3. **`Reply` is not identical at all**
   - zenoh-kotlin: `data class Reply(val replierId: EntityGlobalId?, val result: Result<Sample>)`
   - zenoh-java: sealed hierarchy `Reply.Success` / `Reply.Error`

4. **Other types also embed native-facing behavior or Kotlin-specific conventions**
   - local `Query`, `Liveliness`, `Zenoh`, `Logger`, `Scout`, `Config`, `KeyExpr`, and serialization helpers all currently sit on JNI-facing logic.

So “reuse data types directly” is not just incomplete; for several key public types it is wrong and would break the existing Kotlin API contract.

## Major completeness gap: the plan only covers part of the JNI surface

The plan focuses mostly on Session/pub-sub/query declarations plus advanced pub/sub. But zenoh-kotlin’s current JNI reach is broader:
- `Zenoh.kt` uses `JNIScout`
- `Logger.kt` declares `external fun startLogsViaJNI`
- `liveliness/Liveliness.kt` uses `JNILiveliness`
- `ext/ZSerialize.kt` and `ext/ZDeserialize.kt` use `JNIZBytes`
- `Config.kt`, `KeyExpr.kt`, `Query.kt`, `Scout.kt`, `LivelinessToken.kt`, `ZenohId.kt` all touch JNI-backed types

A JNI-free zenoh-kotlin architecture must explicitly account for all of these surfaces. The current plan would likely leave the worker discovering them late and improvising wrapper boundaries file-by-file.

## What zenoh-java should provide instead

The architecture that fits the goal is a **three-layer split**, not “zenoh-kotlin depends on zenoh-java public API”:

1. **New JNI-backed runtime/core module extracted from zenoh-java**
   - distinct package namespace from `io.zenoh.*` (for example an internal/runtime namespace)
   - owns all JNI, native loading, and Rust integration
   - exposes callback/handler-oriented primitives for session, pub/sub, query, liveliness, scouting, logging, serialization, and advanced pub/sub

2. **zenoh-java public facade**
   - stays exception-based
   - wraps the new runtime/core module
   - continues publishing `io.zenoh.*`

3. **zenoh-kotlin public facade**
   - stays `Result<T>` / `Channel<T>` based
   - wraps the same runtime/core module
   - continues publishing `io.zenoh.*`

This is the only clean way to keep zenoh-kotlin API intact while making it truly JNI-free and avoiding classpath/FQCN collisions.

## zenoh-java-level changes that are actually required

Beyond porting advanced pub/sub, zenoh-java needs structural work:

1. **Extract/publish a lower-level runtime artifact with non-colliding packages**
   - all JNI adapter classes move there
   - all Rust/native build ownership stays there

2. **Move advanced pub/sub support into that runtime artifact**
   - enable `zenoh-ext`
   - port JNI Rust functions for advanced publisher/subscriber, matching listener, sample-miss listener
   - expose runtime-level handles/callback hooks needed by both facades

3. **Move all remaining JNI-backed cross-cutting capabilities there too**
   - scouting
   - liveliness
   - logger/native load lifecycle
   - serialization helpers
   - key expression native helpers
   - query reply primitives

4. **Decide which model types are truly shared**
   - only genuinely API-neutral immutable models should be shared directly
   - if shared publicly, they belong in a separate common-model artifact/module
   - types whose semantics differ between Java and Kotlin facades (`Config`, `KeyExpr`, `Reply`, likely `Query` and declaration handles) must remain facade-specific wrappers

## Bottom line

The plan’s main mistake is choosing the wrong reuse boundary. Porting advanced features into zenoh-java is necessary, but **zenoh-kotlin cannot become JNI-free by depending directly on zenoh-java’s public `io.zenoh.*` library**. The correct prerequisite is a lower-level zenoh-java-owned runtime/core layer with a distinct namespace, after which both zenoh-java and zenoh-kotlin can be thin facades over the same JNI implementation.
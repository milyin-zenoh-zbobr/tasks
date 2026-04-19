## Overall assessment
Most of the migration is in good shape. The build/publication wiring now matches the task requirements, the local JNI layer and in-repo Rust crate are gone, and the wrappers generally follow the `zenoh-java` `common-jni` analog.

However, the final branch still has two task-related issues in the `Query`/`Queryable` adaptation. Both are in code that was rewritten for the runtime migration, and both diverge from the chosen analog.

## Findings

### 1. `Query.acceptsReplies()` no longer uses the runtime-provided `acceptReplies` value
**Severity:** medium

The new runtime callback already provides the accepted reply-key-expression mode explicitly, but the Kotlin wrapper drops that value:
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt:1213-1223` ignores the last `JNIQueryableCallback` parameter (`_`) and constructs `Query(...)` without any accepted-replies information.
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/query/Query.kt:185-193` now infers `acceptsReplies()` indirectly from the `_anyke` selector parameter.

That is weaker than both the analog and the runtime contract:
- `zenoh-java/zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt:676-688` maps the callback’s `acceptReplies` integer directly into `ReplyKeyExpr.entries[acceptReplies]`.
- `zenoh-java/zenoh-java/src/commonMain/kotlin/io/zenoh/query/Query.kt:39-48` stores that value on the `Query` object itself.

Why this matters:
- The task forbids user-level API changes. `Query.acceptsReplies()` is part of the user-visible behavior, and after this migration it is no longer driven by the canonical runtime value.
- The new implementation is brittle against partial changes: if the runtime stops encoding `_anyke` into selector params, or encodes accepted-reply mode differently, Kotlin will silently report the wrong answer even though the callback already delivered the exact enum source.

**Suggested fix:** keep the existing Kotlin API (`acceptsReplies(): ReplyKeyExpr`), but back it with the callback’s `acceptReplies` value instead of re-deriving it from selector parameters. That can be done by adding an internal `ReplyKeyExpr` field to `Query` and passing `ReplyKeyExpr.entries[acceptReplies]` from `Session.resolveQueryable`, while preserving the current public method shape.

### 2. Selector-parameter parsing now fails open instead of surfacing an error
**Severity:** medium

The migrated `Queryable` callback changed selector parsing from explicit failure to silent fallback:
- Current code: `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt:1216-1217` uses `Parameters.from(selectorParams).getOrNull()`.
- Pre-migration code used `getOrThrow()` in the local JNI adapter (`origin/main: zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`, queryable callback block around lines 224-231 in the old file).
- The chosen analog also does not swallow this error: `zenoh-java/zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt:678-680` constructs `Selector(keyExpr2, Parameters.from(selectorParams))` directly.

Why this matters:
- This is a silent failure introduced by the migration. Malformed selector params from JNI/runtime are now converted into `null` parameters and handed to user callbacks as a seemingly valid `Query`.
- That loses information and can also mask the accepted-replies mode, because the current `Query.acceptsReplies()` implementation depends on selector parameters.
- It conflicts with the task guidance to avoid silent defaults and to surface errors explicitly instead of swallowing them.

**Suggested fix:** restore fail-fast behavior here. In Kotlin terms, keep the callback inside `runCatching`, but use `Parameters.from(selectorParams).getOrThrow()` (or an equivalent explicit propagation path) so malformed selector data becomes a failure instead of a degraded `Query` object.

## Analog consistency
Outside of this queryable edge, the migration is largely consistent with the `zenoh-java` analog. The remaining divergence is concentrated in exactly the place where the runtime callback shape changed: `JNIQueryableCallback` now carries `acceptReplies`, but the Kotlin adaptation neither preserves that value nor handles selector parsing as strictly as the analog/base implementation.

## Checklist status
I did not find any remaining unchecked checklist items in the provided task context to mark complete. The task should be re-reviewed after the two issues above are fixed.
## Fixes Applied

### Fix 1: Query.acceptsReplies() backed by runtime value
- Added `private val acceptRepliesValue: ReplyKeyExpr` to `Query` internal constructor (default `MATCHING_QUERY` for safety).
- `acceptsReplies()` now returns `acceptRepliesValue` directly — no more `_anyke` selector param inference.
- Removed unused `REPLY_KEY_EXPR_ANY_SEL_PARAM` constant.
- Public API shape (`fun acceptsReplies(): ReplyKeyExpr`) is unchanged — no user-level breakage.

### Fix 2: Session.resolveQueryable — fail-fast selector params
- `Parameters.from(selectorParams).getOrNull()` changed to `.getOrThrow()`.
- The callback lambda now names `acceptReplies` (was `_`) and passes `ReplyKeyExpr.entries[acceptReplies]` as the last Query constructor argument.

Both changes align with the zenoh-java analog (`common-jni` branch, `Session.kt:676-688`, `Query.kt:47`).

Build verified: `./gradlew :zenoh-kotlin:compileKotlinJvm -Pzenoh.useLocalJniRuntime=true` passes.
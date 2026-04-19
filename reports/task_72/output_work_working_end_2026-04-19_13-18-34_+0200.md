Both review findings are fixed:

1. **`Query.acceptsReplies()`** now uses the `acceptReplies` integer from the JNI callback (`ReplyKeyExpr.entries[acceptReplies]`) stored as an internal field, instead of the fragile `_anyke` selector param inference. Public API is unchanged.

2. **Selector param parsing** now uses `getOrThrow()` so malformed selector data becomes an exception within the `runCatching` block instead of silently becoming a `null` parameter.
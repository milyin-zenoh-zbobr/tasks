The plan is ready for your review. Here's a summary of what it covers:

**What changes and why:**
- Currently Rust throws JVM exceptions via `throw_exception!` → `ZError::throw_on_jvm()`, forcing zenoh-kotlin to use `runCatching` on every call
- New pattern: JNI functions accept `error: Array<String?>` as last param; on failure they write the error message into `error[0]` and return an error-indicator value (0 for pointers, -1 for int/void, null for strings/objects); on success they leave `error` untouched

**Three-layer change:**
1. **Rust (`zenoh-jni`)** — add `set_error_string()` utility; update ~40 exported functions; remove `throw_on_jvm()`
2. **Kotlin runtime (`zenoh-jni-runtime`)** — delete `ZError.kt`; add `error: Array<String?>` to all external funs; remove `@Throws`; update return types (void→Int, Boolean→Int)
3. **Kotlin API (`zenoh-java`)** — create `ZError.kt` here; add error-array creation + indicator checks at every JNI call site; keep `@Throws(ZError::class)` on public API

**Excluded from changes:** free/close/cleanup functions that never fail (`freePtrViaJNI`, `closeSessionViaJNI`, etc.)
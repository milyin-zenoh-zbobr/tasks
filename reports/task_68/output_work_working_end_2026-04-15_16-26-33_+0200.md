All done. The fix was straightforward:

1. **Deleted** `zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt` — `zenoh-jni-runtime` is now the single owner of `io.zenoh.exceptions.ZError`.
2. **Changed** the runtime dep in `zenoh-java/build.gradle.kts` from `implementation` to `api` — so `ZError` is re-exported as part of zenoh-java's public ABI (it appears in `@Throws` across many public classes).

Build passes with all 97 tests green.
# Fix: Duplicate ZError class removed

## Problem (ctx_rec_39)
`io.zenoh.exceptions.ZError` was defined in both `zenoh-jni-runtime` and `zenoh-java` under the same fully-qualified class name, causing classpath shadowing and Android duplicate-class packaging failures.

## Changes made
1. **Deleted** `zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt` — `zenoh-jni-runtime` is now the single authoritative owner.
2. **Changed** `implementation(project(":zenoh-jni-runtime"))` → `api(project(":zenoh-jni-runtime"))` in `zenoh-java/build.gradle.kts`, so `ZError` (used in `@Throws` across zenoh-java's public API) is properly re-exported to downstream consumers.

## Verification
- `gradle :zenoh-java:build` passes.
- All 97 JVM tests pass (1m 21s run).

## Commit
`e881630` — fix: remove duplicate ZError from zenoh-java, expose via api() dep
Overall assessment: the core refactor is in good shape. The Rust/runtime/java boundary now follows the intended analog: `zenoh-jni-runtime` no longer exports `ZError` or throws from JNI adapters, Rust uses sentinel/null returns with `error_out`, and `zenoh-java` recreates `io.zenoh.exceptions.ZError` at the public API layer. I also verified the previously reported runtime adapter issue is fixed: the zbytes serialize runtime APIs now use `ByteArray?`, and the ZenohId path is fully migrated.

However, there is still one blocking correctness issue.

## Blocking finding

### Java callers of `ZSerializer` / `ZDeserializer` were not updated for the new checked-exception contract

`zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerializer.kt:107-113` and `zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZDeserializer.kt:108-115` now declare `@Throws(ZError::class)` on the public JVM API. That is the correct public-layer behavior after this refactor, but the Java call sites below still invoke these methods without either declaring `throws ZError` or catching it:

1. `zenoh-java/src/jvmTest/java/io/zenoh/ZBytesTests.java:39-183`
2. `examples/src/main/java/io/zenoh/ZBytesExamples.java:27-191`

Because these are Java sources calling Kotlin methods annotated with `@Throws`, this is not just a documentation mismatch: the Java compiler treats `ZError` as a checked exception on those calls. As written, these methods no longer satisfy the public API contract and will fail to compile.

### Why this matters

The task intentionally moved exception throwing to the `zenoh-java` layer. Once that public API became checked for Java interop, all Java tests/examples using `serialize()` / `deserialize()` needed to be updated in the same branch. Leaving them unchanged makes the branch incomplete even though the JNI/runtime refactor itself is otherwise consistent.

### Suggested fix

Update the affected Java methods to reflect the checked exception contract, for example by:

1. adding `throws ZError` to the JUnit test methods in `ZBytesTests.java`, and
2. adding `throws ZError` to `ZBytesExamples.main(...)` (or wrapping the calls explicitly).

## Analog consistency

The chosen analog remains correct and is implemented consistently across the JNI/runtime/public layers. This remaining issue is at the Java-consumer edge of the public API: the boundary was changed correctly, but these Java call sites were left in the pre-refactor state.

## Checklist note

I verified the previously pending runtime adapter item is now complete; the remaining blocker is outside that checklist scope.
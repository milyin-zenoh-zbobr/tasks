The updated plan improved one important gap from the prior revision: it now includes the missing JVM/Android zbytes bridge (`JNIZBytes.kt`, `JNIZBytesKotlin.kt`, `ZSerializer.kt`, `ZDeserializer.kt`) and the matching Rust files. That part is good.

However, the plan still has a fundamental architectural problem, so I do not think it is ready for implementation as written.

## Blocking issue: it moves exception throwing into `zenoh-jni-runtime`

The task says:
- `No exception throwing from zenoh-jni-runtime anymore.`
- `No export of error type from zenoh-jni-runtime.`
- `Error type export and throwing exception is performed on zenoh-java level`

But the plan’s “Target API Contract” and Part 4 explicitly say the runtime wrapper should do this:

```kotlin
someViaJNI(/* params */, out)?.let { throw ZError(it) }
```

and Part 5 then says `zenoh-java` can simply call the runtime and propagate `ZError` thrown there.

That is directly contrary to the requested boundary. It would still mean exceptions originate inside `zenoh-jni-runtime`.

## The codebase also makes that direction impossible / wrong

The module graph is one-way:
- `zenoh-java/build.gradle.kts` depends on `project(":zenoh-jni-runtime")`
- there is no reverse dependency from `zenoh-jni-runtime` to `zenoh-java`

So `zenoh-jni-runtime` cannot use `io.zenoh.exceptions.ZError` from `zenoh-java` without introducing a dependency inversion / cycle.

Evidence from the repository:
- `zenoh-java/build.gradle.kts:65` — `api(project(":zenoh-jni-runtime"))`
- `settings.gradle.kts:24-27` — separate sibling modules, with `zenoh-java` layered above runtime
- `zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt` — the only `ZError` definition I found
- `zenoh-jni-runtime/src/**` — no `ZError` class or imports

So the plan currently asks the implementer to make `zenoh-jni-runtime` throw an exception type that lives in a higher-level module that depends on it. That is a fundamental design error, not just a missing detail.

## Why this matters to implementation

A worker following the current plan would likely:
1. change runtime wrappers to throw exceptions,
2. remove error-handling code from `zenoh-java`,
3. then discover runtime has no valid `ZError` to throw and should not throw anyway.

That is exactly the kind of plan ambiguity that can send implementation in the wrong direction.

## What the plan should say instead

The plan should be revised so that:

1. **Rust JNI exports** adopt the new uniform ABI:
   - return `String?` / `jstring` for the error channel
   - write the real result into the `out` parameter
   - never throw Java exceptions from Rust

2. **`zenoh-jni-runtime` stays exception-free**:
   - its JNI declarations change to the new `(…, out) -> String?` shape
   - its public/runtime-layer APIs must not throw `ZError`
   - if helper wrappers are kept, they should surface the error string in a non-exception form consistent with the runtime’s public contract

3. **`zenoh-java` remains the layer that throws `ZError`**:
   - it should call the runtime API
   - translate non-null error strings into `ZError`
   - keep ownership of exception semantics

4. **The same rule applies to the zbytes surface**:
   - `JNIZBytes*` in runtime should adopt the new ABI but not throw
   - `ZSerializer` / `ZDeserializer` in `zenoh-java` should convert the returned error string into `ZError`

## Secondary observation

The plan’s inclusion of the zbytes files is correct and should be kept. The doc-comment restoration item also looks directionally fine. The main issue is not missing coverage anymore; it is the wrong layering of error handling.

## Recommended revision

Revise the plan so the new uniform JNI contract is implemented all the way down, but preserve the module boundary:
- `zenoh-jni` returns error strings
- `zenoh-jni-runtime` exposes error strings / out parameters and does not throw
- `zenoh-java` is the only layer that converts those errors into `ZError`

Until that is fixed, I do not think the plan is sound enough to hand to an implementer.
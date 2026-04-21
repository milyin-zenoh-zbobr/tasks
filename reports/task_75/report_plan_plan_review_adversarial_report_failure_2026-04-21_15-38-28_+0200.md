I reviewed the updated plan from ctx_rec_6 against the codebase. It correctly fixes the previous blocking issue: `zenoh-jni-runtime` must not throw `ZError`, and the zbytes JVM/Android surface is now included. The doc-comment restoration scope also matches the files that actually lost `///` blocks in the branch diff.

However, the plan is still not implementation-ready because Part 4 and Part 5 redefine the runtime API at the wrong abstraction level.

## What the plan gets right

1. **Layering is now correct in principle**
   - `zenoh-java` depends on `zenoh-jni-runtime`, not vice versa.
   - `ZError` lives only in `zenoh-java`.
   - The revised plan no longer asks runtime to throw `ZError`.

2. **The missing zbytes surface is now covered**
   - `zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytes.kt`
   - `zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.kt`
   - `zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerializer.kt`
   - `zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZDeserializer.kt`
   - `zenoh-jni/src/zbytes.rs`
   - `zenoh-jni/src/zbytes_kotlin.rs`

3. **The runtime/common and java/common file coverage is now broadly correct**
   The files listed in the plan line up with the current `error: Array<String?>` / `error_out: JObjectArray` surfaces in the repo.

## Blocking issue: the plan leaks raw native handles past zenoh-jni-runtime

The revised plan says the runtime should become a near-literal passthrough of the native ABI:
- external JNI declarations change to `(…, out) -> String?`
- public runtime API also becomes `fun someOp(..., out: OutType): String?`
- `zenoh-java` then allocates holders like `LongArray(1)` and reads `out[0]`

That is not consistent with how `zenoh-jni-runtime` is structured today.

### The runtime currently owns wrapper-object construction

`zenoh-jni-runtime` does not merely expose raw pointers. It wraps native handles into runtime classes before `zenoh-java` sees them:

- `JNIConfig.loadDefault(...)` returns `JNIConfig?`, not `Long`
  - `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIConfig.kt:28-31`
- `JNISession.open(...)` returns `JNISession?`, not `Long`
  - `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt:31-34`
- `JNISession.declarePublisher(...)` returns `JNIPublisher?`
  - `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt:42-53`
- `JNISession.declareSubscriber(...)` returns `JNISubscriber?`
  - `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt:66-84`
- `JNISession.declareQueryable(...)` returns `JNIQueryable?`
  - `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt:86-106`
- `JNISession.declareQuerier(...)` returns `JNIQuerier?`
  - `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt:108-120`
- `JNIScout.scout(...)` returns `JNIScout?`
  - `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIScout.kt:33-42`
- `JNIAdvancedPublisher.declareMatchingListener(...)` returns `JNIMatchingListener?`
  - `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedPublisher.kt:32-35`

### Why the current plan would mislead an implementer

If a worker follows the current plan literally, they will push raw `LongArray(1)` / `IntArray(1)` handling upward into `zenoh-java`. But `zenoh-java` is not meant to construct runtime wrapper objects from raw handles, and in several cases it cannot cleanly do so because the constructors / raw-handle properties are intentionally kept inside the runtime layer (`internal` or `private` state is used in multiple runtime classes).

So the plan now fixes the exception-layer boundary, but breaks the wrapper-object boundary.

## What the plan should say instead

The plan needs one more architectural correction:

1. **Rust JNI exports** should indeed move to the uniform ABI:
   - return `jstring` / `String?` as the error channel
   - write the real value into an `out` parameter
   - never throw JNI exceptions

2. **Private external functions in `zenoh-jni-runtime`** should match that ABI directly.

3. **Public runtime APIs must preserve the runtime abstraction layer**
   - They should still own conversion from raw native handles into runtime wrapper objects like `JNIConfig`, `JNISession`, `JNIPublisher`, `JNIScout`, `JNIMatchingListener`, etc.
   - They must not throw `ZError`.
   - They may expose the new error contract as `String?`, but the `out` value at the public runtime boundary should be the wrapper object / typed runtime value, not raw JNI internals.

   Concretely, that means the public runtime methods should look more like:
   - `fun loadDefault(out: Array<JNIConfig?>): String?`
   - `fun open(config: JNIConfig, out: Array<JNISession?>): String?`
   - `fun declarePublisher(..., out: Array<JNIPublisher?>): String?`
   rather than pushing `LongArray(1)` into `zenoh-java`.

   For non-handle values, the public runtime API can use the direct typed holders (`IntArray`, `LongArray`, `Array<String?>`, `Array<ByteArray?>`, etc.) where appropriate.

4. **`zenoh-java` remains the only exception-throwing layer**
   - It should receive runtime-level typed results + `String?` error
   - Convert non-null error strings to `ZError`
   - But it should not take ownership of raw native-handle wrapping

## Non-blocking observation

The doc-comment restoration scope appears correct: the files listed in the plan match the Rust files that actually lost `///` blocks in `git diff origin/common-jni...HEAD`.

## Recommendation

Revise the plan so it keeps both boundaries intact:
- **error/exception boundary**: exceptions only in `zenoh-java`
- **native-handle/wrapper boundary**: wrapper-object construction stays in `zenoh-jni-runtime`

Until that is clarified, the plan is still too likely to send implementation in the wrong direction.
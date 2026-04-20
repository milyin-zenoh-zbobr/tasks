The plan has the right general direction, but it is not sound enough to implement as written because its scope does not cover the full surface that currently throws from Rust or depends on the runtime-exported `io.zenoh.exceptions.ZError`.

## 1. The biggest issue: the plan does **not** actually eliminate exception throwing from `zenoh-jni-runtime`

The task requirement is explicit: **no exception throwing from `zenoh-jni-runtime` anymore** and **no export of error type from `zenoh-jni-runtime`**. The plan only migrates the main session/config/keyexpr/query/etc. JNI surface, but there are still native/runtime paths outside that set.

### 1a. `zbytes` / `zbytes_kotlin` are still exception-based

The plan explicitly marks `zbytes.rs` / `zbytes_kotlin.rs` as out of scope, but both still throw from Rust today:
- `zenoh-jni/src/zbytes.rs:177,306`
- `zenoh-jni/src/zbytes_kotlin.rs:188,381`

Those are exposed through runtime helpers:
- `zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytes.kt:20-35`
- `zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.kt:34-49`

If `ZError.kt` is removed from `zenoh-jni-runtime` but these native functions still call `throw_exception!`, runtime-only consumers will be left with JNI functions that still try to resolve `io/zenoh/exceptions/ZError`. That directly violates the task goal and creates a broken half-state.

**Required revision:** either bring both `JNIZBytes`/`JNIZBytesKotlin` native paths into the same sentinel+error-out migration, or explicitly redefine the task scope so that `zenoh-jni-runtime` is still allowed to throw for those APIs (which contradicts the current task statement).

### 1b. `load_on_close` still throws from Rust on callback failure

There is also a non-exported but real Rust→JVM exception path in the callback/on-close plumbing:
- `zenoh-jni/src/utils.rs:163-188`

`load_on_close()` attaches a daemon thread and calls the Java/Kotlin `run()` callback; if that fails it currently does:
- `env.exception_describe()`
- `throw_exception!(env, zerror!(...))`

This path is not representable by the proposed “return sentinel + error array” contract because it is asynchronous and has no caller-owned out-parameter.

**Required revision:** the plan must say what replaces this behavior. The likely answer is to log and stop trying to throw from Rust in callback paths. As written, the plan leaves at least one Rust-side exception path in place, so it does not meet the stated objective.

## 2. The file/call-site inventory is incomplete and would mislead an implementer

Several files that must change if the proposed signature refactor is applied are missing or listed inaccurately.

### 2a. `zenoh_id.rs` is included, but its Kotlin call sites are not

The plan correctly includes:
- `zenoh-jni/src/zenoh_id.rs`

But if `toStringViaJNI` gains `error_out`, the following also must change:
- runtime wrapper: `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIZenohId.kt:20-28`
- API call site: `zenoh-java/src/commonMain/kotlin/io/zenoh/config/ZenohId.kt:23-27`

Neither is listed in Phase 3/4. A worker following the plan literally would miss them.

### 2b. Scouting call site is in `Zenoh.kt`, not `Scout.kt`

The plan says to update `scouting/Scout.kt`, but the actual user-facing entrypoint calling `JNIScout.scout(...)` is:
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Zenoh.kt:54-106`

`Scout.kt` is not the critical call site for the JNI signature change. This is not just a path typo: it points the implementer at the wrong abstraction layer.

### 2c. Exported session JNI functions omitted from scope still throw today

`session.rs` still exports JNI functions not covered by the runtime wrapper list:
- `openSessionWithJsonConfigViaJNI` at `zenoh-jni/src/session.rs:104`
- `openSessionWithYamlConfigViaJNI` at `zenoh-jni/src/session.rs:148`

They still throw from Rust today. If the requirement is truly “no exception throwing from `zenoh-jni-runtime` anymore”, the plan needs to decide whether these are dead/private and can stay as-is, or whether they are also part of the compatibility surface that must be migrated. Right now that decision is missing.

## 3. Verification is too weak for the stated goal

The current verification section would allow a broken implementation to pass.

Examples:
- `grep -rn "throw_exception!" zenoh-jni/src/` only checking exported bodies is insufficient because `utils.rs:163-188` would still violate the goal.
- `grep -rn "ZError" zenoh-jni-runtime/src/` would not catch native code in `zenoh-jni/src/*` still trying to resolve `io/zenoh/exceptions/ZError` after the class is removed from runtime.

**Required revision:** verification should confirm all of the following:
1. No Rust JNI path used by the runtime throws `io/zenoh/exceptions/ZError` anymore.
2. No runtime source still exports or references `io.zenoh.exceptions.ZError`.
3. All Kotlin wrappers whose native signatures changed are updated (`JNIScout`, `JNIZenohId`, etc.), and all API call sites are updated (`Zenoh.kt`, `ZenohId.kt`, etc.).

## Recommendation

Revise the plan before implementation. The plan should be updated to:
1. Include **all** runtime/JNI exception paths that remain, especially `zbytes.rs`, `zbytes_kotlin.rs`, and the runtime wrappers that expose them.
2. Define the replacement behavior for callback/on-close failures in `utils.rs` where an out-parameter contract does not apply.
3. Correct the Kotlin surface inventory so it includes `JNIZenohId.kt`, `zenoh-java/.../config/ZenohId.kt`, and `zenoh-java/.../Zenoh.kt`.
4. Clarify whether currently exported but apparently unused session JNI entrypoints (`openSessionWithJsonConfigViaJNI`, `openSessionWithYamlConfigViaJNI`) are intentionally excluded or must also be migrated.

Until those are addressed, the plan is incomplete and likely to produce an implementation that either still throws from Rust or breaks runtime-only consumers after `ZError` is removed from `zenoh-jni-runtime`. 
# Plan: Adjust zenoh-java JNI to Use Kotlin's Naming Convention

## Context

The overarching goal is to make zenoh-kotlin a thin wrapper over zenoh-java's JNI library, eliminating duplication of Rust JNI code. Task 67 completed Phase 1: adding the JNI function exports needed by zenoh-kotlin to zenoh-java's native library.

Task 68 (this task) is Phase 2: consolidate duplicate JNI function implementations by replacing them with a single JNI function using kotlin's naming variant, minimizing changes on the zenoh-kotlin side.

After thorough exploration, **only one JNI function has a naming difference** between the two codebases:

| Side | JNI function name |
|------|------------------|
| zenoh-java (companion) | `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI` |
| zenoh-kotlin (instance) | `Java_io_zenoh_jni_JNISession_openSessionViaJNI` |

After task 67, zenoh-java's `session.rs` exports **both** variants (companion at line 63, instance alias at line 1227). The task requires removing the companion variant and updating zenoh-java's Kotlin to use the instance variant, making both codebases converge on the single kotlin-style JNI function name.

All other JNI function names (~60+) are already identical between the two codebases.

## Changes Required

### 1. Remove companion variant from Rust (`zenoh-jni/src/session.rs`)

Remove the function `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI` (lines ~55–77, including its doc comment). The instance-method variant `Java_io_zenoh_jni_JNISession_openSessionViaJNI` (added in task 67, at line ~1227) stays as the sole implementation.

### 2. Update zenoh-java's Kotlin JNI adapter (`zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`)

Currently, `openSessionViaJNI` is declared in the `companion object` (lines ~56–57), which causes the `00024Companion` mangling in the JNI symbol name:

```kotlin
companion object {
    fun open(config: Config): JNISession {
        val sessionPtr = openSessionViaJNI(config.jniConfig.ptr)  // companion call
        return JNISession(sessionPtr)
    }
    private external fun openSessionViaJNI(configPtr: Long): Long  // companion declaration
}
```

Move the `external fun` declaration to the class body (instance level). The `open()` factory in companion creates a temporary `JNISession(0L)` instance to call it (the Rust function ignores the receiver `this`/`self` parameter anyway):

```kotlin
companion object {
    fun open(config: Config): JNISession {
        val temp = JNISession(0L)
        val sessionPtr = temp.openSessionViaJNI(config.jniConfig.ptr)  // instance call
        return JNISession(sessionPtr)
    }
    // remove openSessionViaJNI from here
}

// At class body level (generates Java_io_zenoh_jni_JNISession_openSessionViaJNI):
private external fun openSessionViaJNI(configPtr: Long): Long
```

This generates the JNI symbol `Java_io_zenoh_jni_JNISession_openSessionViaJNI` (no `00024Companion`), matching zenoh-kotlin's expectation exactly.

## Critical Files

- `zenoh-jni/src/session.rs` — Remove the companion-variant function at lines ~61–77
- `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt` — Move `openSessionViaJNI` external declaration from companion to class body; update `open()` to create a temp instance

## Rationale

- Kotlin's instance-method style (`Java_io_zenoh_jni_JNISession_openSessionViaJNI`) is the canonical name — it's what zenoh-kotlin uses and generates zero changes on the zenoh-kotlin side
- The Rust function body is identical in both variants (both just call `open_session(config_ptr)`), so removing one has no behavioral impact
- No other JNI function names differ between the two codebases — this is the minimal, targeted change needed

## Verification

1. `cargo build --manifest-path zenoh-jni/Cargo.toml` — confirms Rust compiles cleanly without the companion function
2. `./gradlew build` (or equivalent) — confirms the Kotlin side still compiles with the moved `openSessionViaJNI`
3. Run any existing tests to confirm session opening still works end-to-end

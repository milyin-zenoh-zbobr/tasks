# Plan: Use @JvmStatic to Align openSessionViaJNI JNI Symbol

## Context

The goal is to make zenoh-kotlin a thin wrapper over zenoh-java's JNI library. Task 67 added `Java_io_zenoh_jni_JNISession_openSessionViaJNI` (instance-method form) to `session.rs` alongside the original `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI` (companion form). Both symbols currently exist simultaneously; the Java side still calls the companion one.

The task is to make zenoh-java's Kotlin call the instance-form symbol — the same one zenoh-kotlin uses — and then remove the now-redundant companion form from Rust.

## Why @JvmStatic (addressing the review's concerns)

The review (ctx_rec_2) rejected the previous plan's approach of moving `openSessionViaJNI` to instance scope + creating a fake `JNISession(0L)`, because:
1. It distorts the class model (JNISession is always supposed to wrap a real pointer)
2. It ignored an existing codebase pattern that avoids the hack entirely

That pattern is `@JvmStatic external fun` in companion/object. `JNIZBytes.kt` already uses it:
```kotlin
internal object JNIZBytes {
    @JvmStatic
    external fun serializeViaJNI(any: Any, type: Type): ZBytes
}
```
This generates `Java_io_zenoh_jni_JNIZBytes_serializeViaJNI` — no `$Companion` suffix — because `@JvmStatic` promotes the native binding to the outer class.

The same mechanism applies to `companion object` inside a class: adding `@JvmStatic` to `private external fun openSessionViaJNI` makes Kotlin emit the static native binding on `JNISession` (not `JNISession$Companion`), producing the JNI symbol `Java_io_zenoh_jni_JNISession_openSessionViaJNI`.

## Changes Required

### 1. `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`

Add `@JvmStatic` to the `external fun openSessionViaJNI` declaration in `companion object` (currently line ~57):

```kotlin
// Before:
private external fun openSessionViaJNI(configPtr: Long): Long

// After:
@JvmStatic
private external fun openSessionViaJNI(configPtr: Long): Long
```

No other changes. `open()` factory function and everything else stays identical.

### 2. `zenoh-jni/src/session.rs`

Remove the companion-variant function and its doc comment (lines ~51–77):
- `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI`

The instance-variant `Java_io_zenoh_jni_JNISession_openSessionViaJNI` (at ~line 1227) remains unchanged as the single implementation.

## Critical Files

- `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt` — add `@JvmStatic` to `openSessionViaJNI` declaration in companion object
- `zenoh-jni/src/session.rs` — remove `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI` function (~lines 51–77, including doc comment)

## Rationale / Design Decisions

- `@JvmStatic` on `external fun` is the canonical Kotlin idiom to bind a static native method to the outer class name (no `$Companion`) — proven by `JNIZBytes.kt` in this same repo
- Preserves the `JNISession.open(config): JNISession` factory shape entirely
- Zero change to call site in `open()` factory
- Minimal diff: 1 annotation added, 1 Rust function removed
- zenoh-kotlin side requires zero changes (it already uses `Java_io_zenoh_jni_JNISession_openSessionViaJNI`)

## Verification

1. `cargo build --manifest-path zenoh-jni/Cargo.toml` — Rust compiles cleanly without the companion function
2. Kotlin compilation — `openSessionViaJNI` resolves via `@JvmStatic` to outer-class symbol
3. Run existing tests to confirm session open/close works end-to-end

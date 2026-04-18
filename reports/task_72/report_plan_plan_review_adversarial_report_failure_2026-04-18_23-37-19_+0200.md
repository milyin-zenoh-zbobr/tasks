The migration target is still viable, but the revised plan is **not** sound enough to hand to an implementer yet.

## Blocking issue 1: the plan still treats serialization as a direct swap, but the runtime does not match zenoh-kotlin’s current commonMain contract

`zenoh-kotlin` currently exposes `zSerialize` / `zDeserialize` from **commonMain**, and those functions call `io.zenoh.jni.JNIZBytes` using **`KType`** and **`ZBytes`**:
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/ext/ZSerialize.kt`
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/ext/ZDeserialize.kt`
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIZBytes.kt`

The upstream runtime does **not** provide a drop-in replacement for that surface:
- `zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytes.kt` uses `java.lang.reflect.Type` and `ByteArray`
- `zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.kt` uses `KType`, but it is also in `jvmAndAndroidMain` and still returns `ByteArray`, not `ZBytes`

That means the worker cannot simply delete zenoh-kotlin’s JNI layer and “call zenoh-jni-runtime directly” from current commonMain code. The plan needs an explicit compatibility strategy for this public API, for example:
1. keep a small zenoh-kotlin compatibility wrapper for serialization only, with a non-conflicting internal name, or
2. add an intermediate source set strategy that preserves the existing public API shape without moving `zSerialize` / `zDeserialize` out of commonMain.

Without that, the worker is likely to either break public API/source compatibility or get stuck on the source-set mismatch.

## Blocking issue 2: publication guidance is internally inconsistent and would likely break publishing

The plan correctly says to keep zenoh-kotlin’s publishing/signing setup, but later says to remove `isRemotePublication` usage. That is not safe.

In the current repo, `isRemotePublication` is used for more than JNI bundling:
- `zenoh-kotlin/build.gradle.kts` uses it to require signing for remote publication.

In the upstream runtime, the same property still exists and drives remote-publication behavior:
- `zenoh-jni-runtime/build.gradle.kts`

So the right plan is **not** “remove `isRemotePublication` usage”; it is “remove the zenoh-kotlin-native bundling behavior currently attached to `isRemotePublication`, while preserving the publication-mode/signing control that still matters for Maven publishing.” As written, the plan gives contradictory direction on a release-critical path.

## Important omission: liveliness migration is not mapped cleanly

The revised plan’s delete list is based on the assumption that the runtime mirrors zenoh-kotlin’s JNI class inventory. That is not fully true.

Current zenoh-kotlin has a local helper:
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNILiveliness.kt`
- consumed by `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/liveliness/Liveliness.kt`

The upstream runtime does **not** provide `io.zenoh.jni.JNILiveliness.kt`; instead, liveliness operations live on runtime `JNISession` (`declareLivelinessToken`, `declareLivelinessSubscriber`, `livelinessGet`):
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`

This is fixable, but the plan should say so explicitly. Otherwise a worker following the deletion inventory literally could leave this area half-migrated or choose the wrong compatibility approach.

## Bottom line

The core migration direction is correct: use `org.eclipse.zenoh:zenoh-jni-runtime`, add `zenoh-java` as a gated composite-build submodule for source-based local work, and remove zenoh-kotlin’s own Rust crate.

But the plan is still **not implementation-ready** because it does not cover the public serialization bridge correctly and gives conflicting instructions for release/publication wiring. Those are fundamental enough to send the worker down the wrong path.

## What the revised plan should add

1. **Serialization compatibility plan**: explicitly preserve `zSerialize` / `zDeserialize` public behavior and source-set availability; do not assume runtime `JNIZBytes*` is a direct commonMain replacement.
2. **Publication-mode clarification**: keep `remotePublication` / signing behavior for publishing, while removing only zenoh-kotlin-owned native packaging logic.
3. **Liveliness migration note**: spell out that `Liveliness.kt` must be rewired to runtime `JNISession` liveliness methods (or a small local helper), because there is no runtime `JNILiveliness` class.

With those corrections, the plan should be ready for implementation.
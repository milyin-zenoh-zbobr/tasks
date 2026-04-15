# Implementation Complete

## Summary

Created `zenoh-jni-runtime` as a new Gradle subproject containing public primitive-only JNI adapters. `zenoh-java` now depends on this runtime module instead of containing its own JNI glue code.

## Changes Made

### New `zenoh-jni-runtime` module
- `build.gradle.kts` — Kotlin Multiplatform (jvm + android) with native Rust build task
- `src/commonMain/kotlin/io/zenoh/`:
  - `ZenohLoad.kt` — public `expect object ZenohLoad`
  - `exceptions/ZError.kt` — public `ZError`
  - `jni/JNIConfig.kt` — factory returning `Long` ptr, `loadJson5Config` wrapper
  - `jni/JNIKeyExpr.kt` — primitive API (String/Long returns)
  - `jni/JNISession.kt` — public externals including advanced pub/sub methods
  - `jni/JNIPublisher.kt` — `put(ByteArray, Int, String?, ByteArray?)`
  - `jni/JNIQuery.kt` — `replySuccess/replyDelete/replyError` with primitives
  - `jni/JNIQuerier.kt` — `getViaJNI` external
  - `jni/JNIScout.kt` — companion externals (no `@JvmStatic` to preserve `_00024Companion_` JNI symbol)
  - `jni/JNILiveliness.kt` — object with direct external functions
  - `jni/JNISubscriber.kt`, `JNIQueryable.kt`, `JNILivelinessToken.kt`, `JNIZenohId.kt` — simple ptr wrappers
  - `jni/JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt` — advanced pub/sub adapters
  - `jni/JNIMatchingListener.kt`, `JNISampleMissListener.kt` — simple ptr wrappers
  - `jni/callbacks/` — all 7 callback interfaces (public fun interfaces)
- `src/jvmMain/kotlin/io/zenoh/ZenohLoad.kt` — `public actual object` loading native lib
- `src/jvmMain/kotlin/io/zenoh/Target.kt` — public enum
- `src/androidMain/kotlin/io/zenoh/ZenohLoad.kt` — `public actual object` with `System.loadLibrary`

### `zenoh-java` changes
- `build.gradle.kts` — added runtime dependency, removed duplicate native build tasks
- `Session.kt` — inlined all callback assembly and JNI calls previously in old `JNISession`
- `Zenoh.kt` — inlined `JNIScoutCallback` construction, uses `JNIScout.scoutViaJNI` directly
- `Liveliness.kt` — inlined all JNI ops using `JNILiveliness.*ViaJNI` primitives
- `Querier.kt` — inlined `JNIGetCallback` construction and `getViaJNI` call
- `Publisher.kt` — decompose `IntoZBytes`/`Encoding` to primitives for put/delete
- `Query.kt` — decompose `Sample` to primitives for reply operations
- `Config.kt` — factory methods use `Config(JNIConfig(JNIConfig.loadDefaultConfig()))`
- `keyexpr/KeyExpr.kt` — intersects/includes/relationTo use primitive API
- Deleted all old JNI adapter files from `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/`

### `zenoh-jni` Rust fix
- `src/session.rs` line ~1309 — removed `let subscriber_ptr =` binding that caused missing return value

## Verification
- `gradle :zenoh-java:build` — BUILD SUCCESSFUL
- All 97 existing tests pass (1m 15s)

# Task 68: Adjust zenoh-java Functionality to zenoh-kotlin

## Summary

Created a new `zenoh-jni-runtime` Gradle subproject that contains all JNI adapter classes with primitive-only APIs, enabling `zenoh-kotlin` to be a thin wrapper over `zenoh-java` without duplicating JNI code.

## Changes Made

### New Module: `zenoh-jni-runtime`

**`zenoh-jni-runtime/build.gradle.kts`**
- New module build file owning the `buildZenohJni` Cargo task
- No serialization/dokka/guava dependencies (facade concerns)
- Published as `org.eclipse.zenoh:zenoh-jni-runtime`

**`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt`**
- Moved from zenoh-java; `ZError` must be in runtime since JNI adapters use `@Throws(ZError::class)`

**`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/ZenohLoad.kt`** (expect)
**`zenoh-jni-runtime/src/jvmMain/kotlin/io/zenoh/ZenohLoad.kt`** (actual - full library loading logic)
**`zenoh-jni-runtime/src/androidMain/kotlin/io.zenoh/ZenohLoad.kt`** (actual - System.loadLibrary)
**`zenoh-jni-runtime/src/jvmMain/kotlin/io/zenoh/Target.kt`** (internal enum needed by ZenohLoad)

**Callbacks (all `public`, in `io.zenoh.jni.callbacks`):**
- `JNISubscriberCallback.kt`
- `JNIQueryableCallback.kt`
- `JNIGetCallback.kt`
- `JNIScoutCallback.kt`
- `JNIOnCloseCallback.kt`
- `JNIMatchingListenerCallback.kt` (NEW)
- `JNISampleMissListenerCallback.kt` (NEW)

**JNI Adapters (all `public class`, primitive-only APIs):**
- `JNIConfig.kt` - `public val ptr: Long`, companion static factory methods (without `@JvmStatic` to preserve `_00024Companion_` Rust symbol)
- `JNIKeyExpr.kt` - `public val ptr: Long`, companion static operations (without `@JvmStatic`)
- `JNISession.kt` - `val sessionPtr: Long`, companion `open(configPtr: Long)` with `@JvmStatic openSessionViaJNI`, all session operation externals public
- `JNIPublisher.kt` - `public val ptr: Long`, `put(ByteArray, Int, String?, ByteArray?)`, `delete(ByteArray?)`
- `JNIQuery.kt` - `private val ptr`, public wrapper methods `replySuccess/replyError/replyDelete` with primitives
- `JNIQuerier.kt` - `val ptr: Long`, `get(keyExprPtr, keyExprString, parameters?, callback, onClose, ...)`
- `JNIScout.kt` - companion `fun scout(...)` without `@JvmStatic` (preserves `_00024Companion_` symbol)
- `JNILiveliness.kt` - `public object` with external funs
- `JNILivelinessToken.kt`
- `JNIQueryable.kt`
- `JNISubscriber.kt`
- `JNIAdvancedPublisher.kt` (NEW)
- `JNIAdvancedSubscriber.kt` (NEW)
- `JNIMatchingListener.kt` (NEW)
- `JNISampleMissListener.kt` (NEW)

### Modified: `settings.gradle.kts`
- Added `include(":zenoh-jni-runtime")`

### Modified: `zenoh-java/build.gradle.kts`
- Removed `buildZenohJni` task (now owned by zenoh-jni-runtime)
- Removed native lib resources from jvmMain (now in zenoh-jni-runtime jvmMain)
- Added `implementation(project(":zenoh-jni-runtime"))` in jvmMain dependencies

### Modified: zenoh-java facade classes
All updated to use primitive runtime APIs with inlined callback assembly:

- **`Config.kt`** - wraps `JNIConfig` Long ptr from static factory methods
- **`keyexpr/KeyExpr.kt`** - delegates to `JNIKeyExpr` companion operations
- **`pubsub/Publisher.kt`** - calls `jniPublisher.put(ByteArray, Int, String?, ByteArray?)`
- **`query/Query.kt`** - calls `jniQuery.replySuccess/replyError/replyDelete` with primitives
- **`query/Querier.kt`** - inlines `JNIGetCallback` assembly, calls `jniQuerier.get(...)` directly
- **`Session.kt`** - inlines all subscriber/queryable/get callbacks, uses primitive session APIs
- **`Zenoh.kt`** - inlines `JNIScoutCallback` assembly in all three `scout()` overloads
- **`liveliness/Liveliness.kt`** - inlines get/subscriber callbacks, calls `JNILiveliness` directly
- **`Logger.kt`** - added `ZenohLoad` reference before `startLogsViaJNI`

### Deleted from zenoh-java
- `src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt` (moved to zenoh-jni-runtime)
- `src/jvmMain/kotlin/io/zenoh/ZenohLoad.kt` / `Target.kt`
- `src/androidMain/kotlin/io.zenoh/ZenohLoad.kt`
- All JNI adapter files except `JNIZBytes.kt`
- All callback files

## Build Results

```
:zenoh-jni-runtime:compileKotlinJvm  BUILD SUCCESSFUL
:zenoh-java:compileKotlinJvm         BUILD SUCCESSFUL
:zenoh-java:jvmTest                  SUCCESS: Executed 97 tests in 1m
```

## Key Design Decisions

1. **JNI Symbol Preservation**: Companion objects without `@JvmStatic` produce `_00024Companion_` in Rust symbol names — respected for `JNIConfig`, `JNIKeyExpr`, `JNIScout`.
2. **ZError placement**: Moved to `zenoh-jni-runtime` since JNI adapters use `@Throws(ZError::class)`; zenoh-java inherits it via the runtime dependency.
3. **Primitive-only constraint**: `zenoh-jni-runtime` has zero imports from `io.zenoh.*` facade types.
4. **Cross-module ptr visibility**: `JNIConfig.ptr` and `JNIKeyExpr.ptr` are `public val` for zenoh-java access.

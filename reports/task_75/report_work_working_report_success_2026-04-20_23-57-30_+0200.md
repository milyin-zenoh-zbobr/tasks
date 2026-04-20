# Task Completed

## Summary
Refactored zenoh-java JNI error handling across all layers. Rust JNI functions no longer throw JVM exceptions; instead, the Kotlin layer reads error messages and throws ZError.

## Changes Made

### Rust (`zenoh-jni/`)
- Removed `throw_exception!` macro from `errors.rs`
- Added `set_error_string(env, error_out, msg)` helper
- Updated all fallible JNI functions in: `session.rs`, `config.rs`, `key_expr.rs`, `publisher.rs`, `query.rs`, `querier.rs`, `logger.rs`, `zenoh_id.rs`, `liveliness.rs`, `scouting.rs`, `zbytes.rs`, `zbytes_kotlin.rs`, `ext/advanced_publisher.rs`, `ext/advanced_subscriber.rs`
  - Added `error_out: JObjectArray` parameter
  - Changed return types: void→jint, Boolean→jint, pointers→0L on error

### Kotlin JNI Adapters (`zenoh-jni-runtime/`)
- Deleted `ZError.kt` from exceptions package
- Updated all JNI adapter classes to accept `Array<String?>` error parameter and return nullable/Int types:
  - `JNISession.kt`, `JNIConfig.kt`, `JNIKeyExpr.kt`, `JNIPublisher.kt`, `JNIQuery.kt`, `JNIQuerier.kt`, `JNIScout.kt`, `JNILogger.kt`, `JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt`, `JNIZBytes.kt`, `JNIZBytesKotlin.kt`

### zenoh-java Layer
- Created `ZError.kt` in `zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/`
- Updated all call sites to use error-array pattern:
  - `Session.kt`, `Config.kt`, `KeyExpr.kt`, `Publisher.kt`, `Query.kt`, `Querier.kt`, `Logger.kt`, `Zenoh.kt`, `Liveliness.kt`, `ZSerializer.kt`, `ZDeserializer.kt`

## Verification
- `./gradlew :zenoh-java:compileKotlinJvm` passes (only pre-existing deprecation warnings)
- Zero `ZError` or `@Throws` annotations remain in `zenoh-jni-runtime/`

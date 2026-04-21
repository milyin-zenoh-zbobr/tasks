# JNI API Migration Complete

## Summary
Migrated zenoh-java's JNI API from the old pattern (typed return values + `error: Array<String?>` out-param) to a new uniform pattern where every JNI function returns `String?` (null=success, non-null=error message) and real return values go through typed `out` parameters.

## Changes Made

### Rust JNI (`zenoh-jni`)
- All 40 JNI-exported functions now return `jstring` (null=success, non-null=error message)
- Results go through typed out params (`JObjectArray`, `JLongArray`, `JIntArray`)
- Removed `set_error_string` helper; all use `make_error_jstring`
- Files: config.rs, session.rs, key_expr.rs, publisher.rs, querier.rs, query.rs, liveliness.rs, zbytes.rs, zbytes_kotlin.rs, scouting.rs, logger.rs, zenoh_id.rs, ext/advanced_publisher.rs, ext/advanced_subscriber.rs, errors.rs
- Fixed duplicate `JObject` import in `advanced_subscriber.rs`

### Kotlin Runtime (`zenoh-jni-runtime`)
- All 13 JNI* class files updated; functions return `String?`
- Handle-returning functions use `LongArray` internally, expose `Array<JNI*?>` out param
- No ZError imports or exception throwing
- Files: JNIConfig.kt, JNISession.kt, JNIPublisher.kt, JNIKeyExpr.kt, JNILogger.kt, JNIQuerier.kt, JNIQuery.kt, JNIAdvancedPublisher.kt, JNIAdvancedSubscriber.kt, JNIScout.kt, JNIZenohId.kt, JNIZBytes.kt, JNIZBytesKotlin.kt

### Kotlin Callers (`zenoh-java`)
- All caller files updated to new pattern: `JNI*.method(..., out)?.let { throw ZError(it) }`
- Files: Config.kt, Logger.kt, ZenohId.kt, Publisher.kt, KeyExpr.kt, Querier.kt, Query.kt, Zenoh.kt, Liveliness.kt, Session.kt, ZSerializer.kt, ZDeserializer.kt

## Verification
- `cargo build` (Rust): passes with 12 warnings (all pre-existing)
- `./gradlew compileKotlinJvm`: BUILD SUCCESSFUL with only pre-existing deprecation warnings
- No `ZError`/`set_error_string` in zenoh-jni-runtime
- No old error pattern (`error[0]`, `result < 0`) in zenoh-java callers

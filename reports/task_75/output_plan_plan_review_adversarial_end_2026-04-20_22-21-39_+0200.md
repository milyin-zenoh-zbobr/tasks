● Search (glob)
  │ "**/*jni*"
  └ No matches found

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_3"
  └ # Plan: Throw Exceptions from Java (zenoh-java JNI Error Handling Refact...

I’ve got the proposed refactor. Next I’m checking the actual Rust and Kotlin layers to see whether the plan matches the current code shape, especially around error propagation and JNI signatures.

● Read errors.rs
  │ zenoh-jni/src/errors.rs
  └ L1:220 (59 lines read)

● Read session.rs
  │ zenoh-jni/src/session.rs
  └ L1:260 (259 lines read)

● Read Session.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt
  └ L1:320 (320 lines read)

● Read JNISession.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt
  └ L1:260 (260 lines read)

● Search (grep)
  │ "throw_exception!|throw_on_jvm|ZError|@Throws\(ZError::class\)|external fun
  │ .*ViaJNI|set_error_string" in
  │ {zenoh-jni,zenoh-jni-runtime,zenoh-java}/**/*.{rs,kt}
  └ 8 lines found

I’m seeing the basic structure the plan assumes, but there are already a couple of places where it may be underspecified. I’m drilling into the actual exported function set and the Kotlin adapters before deciding whether this is implementable as written.

✗ Read Config.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/config/Config.kt
  └ Path does not exist

● Search (grep)
  │ "@Throws\(ZError::class\)" in **/*.kt
  │ (zenoh-jni-runtime/src/commonMain/kotlin)
  └ 10 files found

● Search (grep)
  │ "throw_exception!\(" in **/*.rs (zenoh-jni/src)
  └ 15 files found

● Search (grep)
  │ "external fun .*ViaJNI" in **/*.kt (zenoh-jni-runtime/src/commonMain/kotlin)
  └ 64 lines found

● Search (grep)
  │ "pub .*extern \"C\" fn Java_io_zenoh_jni_.*ViaJNI" in **/*.rs
  │ (zenoh-jni/src)
  └ 55 lines found

● Read ZError.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt
  └ L1:80 (20 lines read)

● Read KeyExpr.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/keyexpr/KeyExpr.kt
  └ L1:260 (187 lines read)

● Read JNIConfig.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIConfig.kt
  └ L1:220 (79 lines read)

● Read JNIKeyExpr.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIKeyExpr.kt
  └ L1:220 (82 lines read)

● Read Config.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt
  └ L1:260 (159 lines read)

● Read Zenoh.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Zenoh.kt
  └ L1:160 (145 lines read)

● Read config.rs
  │ zenoh-jni/src/config.rs
  └ L1:240 (184 lines read)

● Read key_expr.rs
  │ zenoh-jni/src/key_expr.rs
  └ L1:280 (280 lines read)

I’ve confirmed the broad pattern exists, but there’s a likely mismatch with the stated end goal: the runtime currently exports `ZError` beyond the files listed in the plan, and there are native paths outside the proposed refactor set that still throw. I’m checking whether those are truly unused or whether the plan would leave the runtime in a half-migrated state.

✗ Read JNIZBytesKotlin.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.kt
  └ Path does not exist

● Read zbytes_kotlin.rs
  │ zenoh-jni/src/zbytes_kotlin.rs
  └ L150:430 (281 lines read)

● Read build.gradle.kts
  │ zenoh-jni-runtime/build.gradle.kts
  └ L1:220 (220 lines read)

● Read build.gradle.kts
  │ zenoh-java/build.gradle.kts
  └ L1:240 (201 lines read)

● Search (grep)
  │ "import
  │ io\.zenoh\.exceptions\.ZError|@Throws\(ZError::class\)|throw_exception!\("
  │ in {zenoh-jni,zenoh-jni-runtime,zenoh-java}/**/*.{rs,kt}
  └ 7 lines found

● Search (grep)
  │ "throw_exception!\(" in **/*.rs (zenoh-jni/src)
  └ 55 lines found

● Search (grep)
  │ "import io\.zenoh\.exceptions\.ZError" in **/*.kt
  │ (zenoh-jni-runtime/src/commonMain/kotlin)
  └ 10 lines found

● Search (glob)
  │ "**/*ZBytes*Kotlin*.kt" in zenoh-jni-runtime/src
  └ 1 file found

● Search (grep)
  │ "JNIZBytesKotlin|serializeViaJNI\(|deserializeViaJNI\(" in
  │ {zenoh-jni-runtime,zenoh-java}/**/*.kt
  └ 67 lines found

● Search (grep)
  │ "package io\.zenoh\.exceptions" in **/ZError.kt
  └ 1 line found

● Read JNIZBytes.kt
  │ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytes.kt
  └ L1:120 (35 lines read)

● Read query.rs
  │ zenoh-jni/src/query.rs
  └ L1:220 (206 lines read)

● Read utils.rs
  │ zenoh-jni/src/utils.rs
  └ L150:230 (40 lines read)

● Read JNIScout.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIScout.kt
  └ L1:120 (56 lines read)

● Read JNIZBytesKotlin.kt
  │ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.
  │ kt
  └ L1:120 (49 lines read)

The main issue is getting clearer: the plan is scoped as if only the `zenoh-java` API surface matters, but the requirement is stronger than that. I’m now checking for runtime/JNI exports that would still throw or still require `io.zenoh.exceptions.ZError` even if the listed files were updated.

● Search (grep)
  │ "toString\(|JNIZenohId|ZenohId\(" in **/*.kt
  │ (zenoh-java/src/commonMain/kotlin)
  └ 33 lines found

● Search (grep)
  │ "openSessionWithJsonConfigViaJNI|openSessionWithYamlConfigViaJNI" in
  │ {zenoh-jni,zenoh-jni-runtime,zenoh-java}/**/*.{rs,kt}
  └ 2 lines found

● Search (grep)
  │ "set_error_string|JObjectArray|Array<String\?>" in
  │ {zenoh-jni,zenoh-jni-runtime,zenoh-java}/**/*.{rs,kt}
  └ 3 lines found

● Read ZenohId.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/config/ZenohId.kt
  └ L1:160 (58 lines read)

● Read zenoh_id.rs
  │ zenoh-jni/src/zenoh_id.rs
  └ L1:120 (42 lines read)

● Read JNIZenohId.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIZenohId.kt
  └ L1:120 (29 lines read)

I found one more architectural hole: not every remaining exception comes from a synchronous JNI API that can be converted to “return sentinel + out-error”. There’s at least one callback-driven path that currently throws from Rust on a background-attached JVM thread, and the plan doesn’t say what replaces that behavior.

✗ Read queryable_callback.rs
  │ zenoh-jni/src/queryable_callback.rs
  └ Path does not exist

✗ Read subscriber_callback.rs
  │ zenoh-jni/src/subscriber_callback.rs
  └ Path does not exist

● Search (grep)
  │ "exception_describe|call_method\(|throw_exception!\(" in **/*callback*.rs
  │ (zenoh-jni/src)
  └ 1 line found

● Search (grep)
  │ "load_on_close\(|onClose|JNIOnCloseCallback" in **/*.rs (zenoh-jni/src)
  └ 21 lines found

● Read sample_callback.rs
  │ zenoh-jni/src/sample_callback.rs
  └ L1:220 (138 lines read)

● Search (grep)
  │ "JNIZBytesKotlin|JNIZBytes" in **/*.kt (zenoh-java/src)
  └ 4 lines found

● Search (grep)
  │ "ZN?Error|io\.zenoh\.exceptions" in **/*.kt
  │ (zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin)
  └ No matches found

● Search (grep)
  │ "JNIZenohId" in **/*.kt (zenoh-java/src)
  └ 2 lines found

● report_failure (MCP: zbobr) · brief: "Plan is not ready: it leaves JNI/runtime exception paths an…
  └ Report stored

Plan review failed: it leaves real JNI/runtime exception paths outside scope, so implementing it as written would not meet the stated goal.

The main blockers are that `zbytes.rs` / `zbytes_kotlin.rs` still throw from Rust while the plan removes `ZError` from `zenoh-jni-runtime`, and `utils.rs` still throws from Rust in the `load_on_close()` callback path where the proposed out-parameter pattern cannot apply. The file inventory is also incomplete: `zenoh_id.rs` is listed, but the required Kotlin changes in `JNIZenohId.kt` and `zenoh-java/.../config/ZenohId.kt` are missing, and the scouting call site is actually in `Zenoh.kt`, not `Scout.kt`.

--- stderr ---

Changes   +0 -0
Requests  1 Premium (3m 1s)
Tokens    ↑ 697.5k • ↓ 8.3k • 621.7k (cached) • 2.9k (reasoning)
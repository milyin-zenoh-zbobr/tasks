● Search (glob)
  │ "zenoh-java/**/*.rs"
  └ No matches found

● Search (glob)
  │ "zenoh-jni-runtime/**/*.rs"
  └ No matches found

● Search (grep)
  │ "throw_new|Exception|JNIEnv|JString|jbyteArray|zbytes|serialize|deserialize"
  │ in zenoh-{jni-runtime,java}/**/*.rs
  └ No matches found

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_8"
  └ # Implementation Plan: Uniform JNI Error API (String? return + out param...

I’ve got the latest plan. Now I’m checking the repository layout and current JNI/error-handling surfaces to see whether its assumptions match the code that actually exists.

● Search (glob)
  │ "**/*.rs"
  └ 24 files found

● Search (glob)
  │ "**/*.kt"
  └ 78 files found

● List directory .
  └ 28 files found

● Inspect branch and diff (shell)
  │ git --no-pager branch --show-current && printf '\n---\n' && git --no-pager
  │ status --short && printf '\n---\n' && git --no-pager diff --stat
  │ origin/common-jni...HEAD
  └ 52 lines...

The branch already has broad in-flight changes, so I’m validating the plan against the current implementation rather than the original design docs. I’m focusing on the real JNI signatures, runtime wrappers, and the zbytes JVM/Android path the earlier reviews called out.

● Read errors.rs
  │ zenoh-jni/src/errors.rs
  └ 51 lines read

● Read JNISession.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt
  └ L1:260 (260 lines read)

● Read Session.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt
  └ L1:260 (260 lines read)

● Read JNIZBytes.kt
  │ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytes.kt
  └ L1:220 (35 lines read)

● Search (grep)
  │ "throw_new|set_error_string|make_error_jstring|error:
  │ Array<String\?>|Array<String\?>\)|LongArray\)|arrayOfNulls|ZError|out:
  │ Array|out: LongArray|ViaJNI" in
  │ {zenoh-jni/**/*.rs,zenoh-jni-runtime/**/*.kt,zenoh-java/**/*.kt}
  └ 8 lines found

● Search (grep)
  │ "import io\.zenoh\.exceptions\.ZError|throw ZError" in **/*.kt
  │ (zenoh-jni-runtime/src)
  └ No matches found

● Read zbytes.rs
  │ zenoh-jni/src/zbytes.rs
  └ L1:260 (260 lines read)

● Read JNIZBytesKotlin.kt
  │ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.
  │ kt
  └ L1:220 (49 lines read)

● Read zbytes_kotlin.rs
  │ zenoh-jni/src/zbytes_kotlin.rs
  └ L1:260 (260 lines read)

● Search (grep)
  │ "error: Array<String\?>|Array<String\?>\):
  │ (Long|Int|ByteArray\?|Any\?|String\?|List<ByteArray>\?)|private external fun
  │ .*ViaJNI|fun .*\(.*error: Array<String\?>" in **/*.kt
  │ (zenoh-jni-runtime/src)
  └ 7 lines found

● Find removed rust doc comments (shell)
  │ git --no-pager diff origin/common-jni...HEAD -- zenoh-jni/src | rg
  │ '^-\s*///' -n || true
  └ 2 lines...

I’ve confirmed the runtime currently still uses the old `error: Array<String?>` + typed return pattern, and the Rust side still uses `set_error_string`. Next I’m checking whether the plan’s file coverage and proposed ABI details line up with all changed JNI entry points, especially doc-comment restoration and object-returning surfaces.

● Read session.rs
  │ zenoh-jni/src/session.rs
  └ L1:260 (260 lines read)

● Read config.rs
  │ zenoh-jni/src/config.rs
  └ L1:220 (164 lines read)

● Read JNIConfig.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIConfig.kt
  └ L1:220 (70 lines read)

● Read ZSerializer.kt
  │ zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerializer.kt
  └ L1:220 (114 lines read)

● List deleted rust doc comments (shell)
  │ git --no-pager diff origin/common-jni...HEAD -- zenoh-jni/src | grep -nE
  │ '^-\s*///' || true
  └ 15 lines...

● Read ZDeserializer.kt
  │ zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZDeserializer.kt
  └ L1:220 (116 lines read)

● Read copilot-tool-output-1776779508595-zp5kmx.txt
  │ /tmp/copilot-tool-output-1776779508595-zp5kmx.txt
  └ L1:260 (260 lines read)

● Read advanced_publisher.rs
  │ zenoh-jni/src/ext/advanced_publisher.rs
  └ L1:220 (220 lines read)

● Read queryable.rs
  │ zenoh-jni/src/queryable.rs
  └ L1:220 (41 lines read)

● Read JNIAdvancedPublisher.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedPublisher.kt
  └ L1:220 (64 lines read)

● Read JNIKeyExpr.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIKeyExpr.kt
  └ L1:240 (69 lines read)

● Read Config.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt
  └ L1:220 (168 lines read)

● Read copilot-tool-output-1776779479237-3ddzrx.txt
  │ /tmp/copilot-tool-output-1776779479237-3ddzrx.txt
  └ L1:260 (91 lines read)

● Search (grep)
  │ "openSessionWith(Json|Yaml)ConfigViaJNI|load(Json|Yaml)ConfigViaJNI|open\(co
  │ nfig|loadFromJson|loadFromYaml" in
  │ {zenoh-jni/**/*.rs,zenoh-jni-runtime/**/*.kt,zenoh-java/**/*.kt}
  └ 41 lines found

● Read KeyExpr.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/keyexpr/KeyExpr.kt
  └ L1:260 (200 lines read)

● Read key_expr.rs
  │ zenoh-jni/src/key_expr.rs
  └ L1:260 (221 lines read)

● Read JNILogger.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNILogger.kt
  └ L1:120 (34 lines read)

● Read Logger.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Logger.kt
  └ L1:120 (39 lines read)

I found a real gap: the plan now fixes pointer/object-returning APIs, but it still doesn’t define the new `out`-parameter treatment for scalar-returning JNI methods (`Boolean`/`Int`-like results), and several existing runtime/Java surfaces with that shape still exist in this branch. I’m checking the remaining classes that carry those returns so I can judge whether that omission is merely editorial or likely to misdirect implementation.

● Read JNIZenohId.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIZenohId.kt
  └ L1:120 (29 lines read)

● Read ZenohId.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/config/ZenohId.kt
  └ L1:140 (61 lines read)

● Read JNIQuerier.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIQuerier.kt
  └ L1:120 (55 lines read)

● Read JNIQuery.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIQuery.kt
  └ L1:160 (88 lines read)

● Read JNIAdvancedSubscriber.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedSubscriber.k
  │ t
  └ L1:180 (81 lines read)

● report_failure (MCP: zbobr) · brief: "The plan is close, but it still omits the scalar-return JNI…
  └ Report stored

Implemented review result: **the plan is not implementation-ready**.

I reported a failure because it still misses the new `String?` + `out` contract for **scalar-returning JNI methods** and omits several active JNI/runtime/java surfaces (`JNIKeyExpr`, `JNIZenohId`, `JNILogger`, `JNIQuerier`, `JNIQuery`, and parts of the advanced publisher/subscriber APIs). I also flagged that the proposed `make_error_jstring` helper can collapse a real error into the `null` success sentinel if `env.new_string(...)` fails.

--- stderr ---

Changes   +0 -0
Requests  1 Premium (5m 56s)
Tokens    ↑ 559.3k • ↓ 8.6k • 428.5k (cached) • 4.2k (reasoning)
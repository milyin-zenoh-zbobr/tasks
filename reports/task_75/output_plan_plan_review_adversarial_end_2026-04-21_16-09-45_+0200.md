● Search (glob)
  │ "**/*.{rs,java,kt}"
  └ 138 files found

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_10"
  └ # Implementation Plan: Uniform JNI Error API (String? return + out param...

I’m checking the actual JNI/runtime surfaces now to see whether the plan’s coverage and layering assumptions match the code, especially around scalar returns and JVM/Android byte helpers.

● Search (grep)
  │ "throw ZError|import io\.zenoh\.exceptions\.ZError" in **/*.kt
  │ (zenoh-jni-runtime/src)
  └ No matches found

● Search (grep)
  │ "external fun .*ViaJNI|fun .*ViaJNI" in **/*.kt (zenoh-jni-runtime/src)
  └ 84 lines found

● Search (grep)
  │ "pub extern "system" fn Java_.*ViaJNI" in **/*.rs (zenoh-jni/src)
  └ No matches found

● Search (grep)
  │ "throw ZError" in **/*.kt (zenoh-java/src)
  └ 59 lines found

● Show changed files vs common-jni (shell)
  │ git --no-pager diff --stat origin/common-jni...HEAD && printf '\n---\n' &&
  │ git --no-pager diff --name-only origin/common-jni...HEAD -- zenoh-jni/src
  └ 65 lines...

● Read JNIKeyExpr.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIKeyExpr.kt
  └ L1:220 (69 lines read)

● Read JNIConfig.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIConfig.kt
  └ L1:180 (70 lines read)

● Read JNIZBytes.kt
  │ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytes.kt
  └ L1:120 (35 lines read)

● Read JNIZBytesKotlin.kt
  │ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.
  │ kt
  └ L1:140 (49 lines read)

● Read errors.rs
  │ zenoh-jni/src/errors.rs
  └ L1:220 (51 lines read)

● Read JNISession.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt
  └ L1:420 (385 lines read)

● Check doc comment deletions/additions (shell)
  │ git --no-pager diff origin/common-jni...HEAD -- zenoh-jni/src | rg -n
  │ '^-///|^\+///'
  └ 2 lines...

I found the current runtime still using the old `error: Array<String?>` + typed return shape everywhere, so the main question is whether the final plan covers every exposed native surface and preserves the runtime/java layering cleanly.

● Read key_expr.rs
  │ zenoh-jni/src/key_expr.rs
  └ L1:260 (221 lines read)

● Read session.rs
  │ zenoh-jni/src/session.rs
  └ L1:320 (320 lines read)

● Read ZDeserializer.kt
  │ zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZDeserializer.kt
  └ L100:135 (17 lines read)

● Read zbytes.rs
  │ zenoh-jni/src/zbytes.rs
  └ L1:220 (220 lines read)

● Read ZSerializer.kt
  │ zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerializer.kt
  └ L90:135 (25 lines read)

● Read zbytes_kotlin.rs
  │ zenoh-jni/src/zbytes_kotlin.rs
  └ L1:220 (220 lines read)

● Search (grep)
  │ "pub extern "system" fn Java_.*ViaJNI" in **/*.rs (zenoh-jni/src)
  └ No matches found

● Search (grep)
  │ "set_error_string\(|throw_new|Exception" in **/*.rs (zenoh-jni/src)
  └ 54 lines found

● Search (grep)
  │ "openSessionWithJsonConfigViaJNI|openSessionWithYamlConfigViaJNI" in
  │ **/*.{kt,rs,java}
  └ 2 lines found

● Search (grep)
  │ "jint \{|-> jint|-> \*const|-> jobject|-> jbyteArray|-> jstring" in **/*.rs
  │ (zenoh-jni/src)
  └ 54 lines found

● List rust doc comment diff lines (shell)
  │ git --no-pager diff origin/common-jni...HEAD -- zenoh-jni/src | grep -nE
  │ '^[+-]///' | head -200
  └ 201 lines...

● Read JNIScout.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIScout.kt
  └ L1:120 (58 lines read)

● Read JNIAdvancedPublisher.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedPublisher.kt
  └ L1:140 (64 lines read)

● Read JNIAdvancedSubscriber.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedSubscriber.k
  │ t
  └ L1:140 (81 lines read)

● Read JNIQuery.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIQuery.kt
  └ L1:130 (88 lines read)

● Read Zenoh.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Zenoh.kt
  └ L45:130 (86 lines read)

● Read JNIQuerier.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIQuerier.kt
  └ L1:90 (55 lines read)

● Search (grep)
  │ "openSessionWithJsonConfigViaJNI|openSessionWithYamlConfigViaJNI|openSession
  │ ViaJNI" in **/*.kt (zenoh-jni-runtime/src)
  └ 2 lines found

● Search (grep)
  │ "JNIZBytesKotlin|JNIZBytes\." in **/*.kt (zenoh-java/src)
  └ 2 lines found

● Search (grep)
  │ "declareBackground|getMatchingStatus\(|intersects\(|includes\(|relationTo\("
  │ in **/*.kt (zenoh-java/src/commonMain/kotlin)
  └ 6 lines found

● Read ZBytesInteropTests.kt
  │ zenoh-jni-runtime/src/jvmTest/kotlin/io/zenoh/ZBytesInteropTests.kt
  └ L1:220 (220 lines read)

● Read KeyExpr.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/keyexpr/KeyExpr.kt
  └ L75:170 (96 lines read)

● Read Logger.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Logger.kt
  └ L25:60 (15 lines read)

● Search (grep)
  │ "JNIZBytesKotlin" in **/*.{kt,java}
  └ 61 lines found

I found one concrete gap already: the plan’s surface map skips the standalone `JNIPublisher` wrapper even though `zenoh-java` calls it directly for `Publisher.put/delete`. I’m checking whether that’s the only missed runtime surface or part of a broader pattern.

● Search (grep)
  │ "JNIAdvancedPublisher|JNIAdvancedSubscriber|JNIPublisher|JNIQuery|JNIQuerier
  │ |JNISession|JNIConfig|JNIKeyExpr|JNIZenohId|JNILogger|JNIScout" in **/*.kt
  │ (zenoh-java/src/commonMain/kotlin)
  └ 56 lines found

● Search (grep)
  │ "private external fun .*error: Array<String\?>" in **/*.kt
  │ (zenoh-jni-runtime/src)
  └ 9 files found

● Read JNIPublisher.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIPublisher.kt
  └ L1:120 (40 lines read)

● Read Publisher.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/pubsub/Publisher.kt
  └ L70:125 (55 lines read)

● Search (grep)
  │ "declareBackgroundMatchingListener|getMatchingStatus|declareBackgroundDetect
  │ PublishersSubscriber|declareBackgroundSampleMissListener|declareMatchingList
  │ ener|declareSampleMissListener" in **/*.kt (zenoh-java/src)
  └ No matches found

● Search (glob)
  │ "zenoh-java/src/commonMain/kotlin/io/zenoh/**/*.kt"
  └ 45 files found

● Search (grep)
  │ "class AdvancedPublisher|class
  │ AdvancedSubscriber|MatchingListener|SampleMissListener" in **/*.kt
  │ (zenoh-java/src)
  └ No matches found

I’ve finished the codebase cross-check. The plan is close, but one missing runtime surface is enough to send an implementer down the wrong path, so I’m marking it for revision.

● report_failure (MCP: zbobr) · brief: "Plan is not implementation-ready: it omits the direct JNIPu…
  └ Report stored

Reported **failure**: the plan still isn’t implementation-ready.

The blocking issue is that it **omits `JNIPublisher`** from the runtime surface map, even though `zenoh-java` uses `JNIPublisher.put/delete` directly in `zenoh-java/src/commonMain/kotlin/io/zenoh/pubsub/Publisher.kt`. That leaves a real path where the worker could migrate session-level calls but miss publisher-level calls entirely.

I also flagged a scope inconsistency in `zenoh-jni/src/session.rs`: the plan says all JNI exports should move to `String?` + `out`, but it does not account for the still-exported `openSessionWithJsonConfigViaJNI` / `openSessionWithYamlConfigViaJNI` functions. The plan needs to either include them in the migration or explicitly mark them as legacy/out of scope.

--- stderr ---

Changes   +0 -0
Requests  1 Premium (5m 2s)
Tokens    ↑ 747.4k • ↓ 8.0k • 678.3k (cached) • 3.8k (reasoning)
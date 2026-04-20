● Get task commits and changed files (shell)
  │ git --no-pager log --oneline origin/common-jni..HEAD && printf
  │ '\n---DIFF---\n' && git --no-pager diff --stat origin/common-jni...HEAD &&
  │ printf '\n---FILES---\n' && git --no-pager diff --name-only
  │ origin/common-jni...HEAD
  └ 179 lines...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_7"
  └ # Plan: Throw Exceptions from Java (zenoh-java JNI Error Handling Refact...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_34"
  └ ## Final Fix: Java ZBytes Call Sites

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_29"
  └ Overall assessment: the analog and implementation pattern are good acros...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_33"
  └ Overall assessment: the core refactor is in good shape. The Rust/runtime...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_31"
  └ Overall assessment: the main architectural refactor is now in place and ...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_8"
  └ I reviewed the revised plan in ctx_rec_7 against the current `common-jni...

I’ve got the branch shape and prior review history; now I’m checking the remaining edge cases where this refactor could still be half-migrated or inconsistent across Rust/runtime/public API layers.

● Search (grep)
  │ "serialize\(|deserialize\(" in **/*.{kt,java} (examples/src)
  └ 26 lines found

● Search (grep)
  │ "serialize\(|deserialize\(|loadDefault\(|toString\(" in **/*.{kt,java}
  │ (zenoh-java/src)
  └ 94 lines found

● Search (grep)
  │ "ZError|@Throws" in **/*.{kt,kts} (zenoh-jni-runtime/src)
  └ No matches found

● Search (grep)
  │ "throw_exception!|throw_on_jvm|KOTLIN_EXCEPTION_NAME" in **/*.rs
  │ (zenoh-jni/src)
  └ No matches found

● Search (grep)
  │ "Array<String\?>|arrayOfNulls<String>\(1\)|ByteArray\?|Any\?" in **/*.kt
  │ (zenoh-jni-runtime/src)
  └ 7 lines found

The obvious regressions from earlier reviews look fixed, so I’m reading the specific API surfaces that tend to leak inconsistencies: public `@Throws` metadata, runtime zbytes typing, and the Rust error helper/wrapper signatures.

● Read Config.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt
  └ L1:140 (140 lines read)

● Read ZenohId.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/config/ZenohId.kt
  └ L1:80 (61 lines read)

● Read ZSerializer.kt
  │ zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerializer.kt
  └ L100:125 (15 lines read)

● Read ZDeserializer.kt
  │ zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZDeserializer.kt
  └ L100:125 (17 lines read)

● Read JNIZBytes.kt
  │ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytes.kt
  └ L1:80 (35 lines read)

● Read JNIZBytesKotlin.kt
  │ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.
  │ kt
  └ L1:90 (49 lines read)

● Read JNIZenohId.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIZenohId.kt
  └ L1:60 (29 lines read)

● Read errors.rs
  │ zenoh-jni/src/errors.rs
  └ L1:120 (51 lines read)

● Read ZBytesTests.java
  │ zenoh-java/src/jvmTest/java/io/zenoh/ZBytesTests.java
  └ L1:70 (69 lines read)

● Read ZBytesExamples.java
  │ examples/src/main/java/io/zenoh/ZBytesExamples.java
  └ L1:35 (35 lines read)

● Search (grep)
  │ "= JNI[A-Z][A-Za-z0-9_]*\(|: JNI[A-Z][A-Za-z0-9_]*\??|ptr == 0L|return null"
  │ in **/*.kt (zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni)
  └ 100 lines found

● Search (grep)
  │ "external fun .*Boolean|external fun .*String\b|external fun
  │ .*ByteArray\b|external fun .*Unit\b" in **/*.kt
  │ (zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni)
  └ 24 lines found

● Search (grep)
  │ "Array<String\?>" in **/*.kt
  │ (zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni)
  └ 11 files found

● Search (grep)
  │ "throw ZError\(" in **/*.kt (zenoh-java/src)
  └ 59 lines found

● Search (grep)
  │ "@Throws\(ZError::class\)" in **/*.kt (zenoh-java/src)
  └ 14 files found

● Read JNIConfig.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIConfig.kt
  └ L1:90 (70 lines read)

● Read config.rs
  │ zenoh-jni/src/config.rs
  └ L1:140 (140 lines read)

● Read ConfigTest.java
  │ zenoh-java/src/jvmTest/java/io/zenoh/ConfigTest.java
  └ L150:180 (31 lines read)

● Read PublisherTest.java
  │ zenoh-java/src/jvmTest/java/io/zenoh/PublisherTest.java
  └ L1:60 (60 lines read)

● Read SessionInfoTest.java
  │ zenoh-java/src/jvmTest/java/io/zenoh/SessionInfoTest.java
  └ L95:115 (17 lines read)

● Search (grep)
  │ "throw_exception!" in **/*.rs (zenoh-jni/src)
  └ No matches found

● Search (glob)
  │ "**/ZError.kt"
  └ 1 file found

● Search (grep)
  │ "error_out: JObjectArray" in **/*.rs (zenoh-jni/src)
  └ 14 files found

I’m down to consistency checks now: looking for places where the new JNI sentinel contract exists in Rust/runtime but the zenoh-java layer still calls an old convenience wrapper or misses Java-facing exception metadata.

● Read Zenoh.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Zenoh.kt
  └ L1:150 (150 lines read)

● Read Logger.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Logger.kt
  └ L1:80 (39 lines read)

● Read Liveliness.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/liveliness/Liveliness.kt
  └ L1:260 (256 lines read)

● Read JNIAdvancedPublisher.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedPublisher.kt
  └ L1:90 (64 lines read)

● Read utils.rs
  │ zenoh-jni/src/utils.rs
  └ L150:205 (37 lines read)

● Read JNIAdvancedSubscriber.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedSubscriber.k
  │ t
  └ L1:100 (81 lines read)

● Read ZBytesInteropTests.kt
  │ zenoh-jni-runtime/src/jvmTest/kotlin/io/zenoh/ZBytesInteropTests.kt
  └ L1:260 (259 lines read)

● Read ZError.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt
  └ L1:40 (20 lines read)

● Search (grep)
  │ "getMatchingStatus\(" in **/*.{kt,java}
  └ 1 line found

● Search (grep)
  │ "declareMatchingListener\(|declareBackgroundMatchingListener\(|declareDetect
  │ PublishersSubscriber\(|declareBackgroundDetectPublishersSubscriber\(|declare
  │ SampleMissListener\(|declareBackgroundSampleMissListener\(" in
  │ **/*.{kt,java}
  └ 6 lines found

I’m doing one last sweep for Kotlin public methods that now throw `ZError` but may have lost `@Throws(ZError::class)`, since that’s the main kind of Java-facing regression left after the JNI pieces are fixed.

● Double-check runtime has no thrown ZError (shell)
  │ python - <<'PY'
  │ from pathlib import Path
  │ root = Path('/data/home/skynet/tasks/base/workspaces/zenoh-java/task-75/ze
  │ noh-java/zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni')
  │ for path in root.rglob('*.kt'):…
  └ 6 lines...

● Find throw ZError methods without @Throws (shell)
  │ python - <<'PY'
  │ from pathlib import Path
  │ root = Path('/data/home/skynet/tasks/base/workspaces/zenoh-java/task-75/ze
  │ noh-java/zenoh-java/src')
  │ for path in root.rglob('*.kt'):…
  └ 18 lines...

● Double-check runtime has no thrown ZError (shell)
  │ python3 - <<'PY'
  │ from pathlib import Path
  │ root = Path('/data/home/skynet/tasks/base/workspaces/zenoh-java/task-75/ze
  │ noh-java/zenoh-jni-runtime/src')
  │ for path in root.rglob('*.kt'):…
  └ 5 lines...

● Find throw ZError methods without @Throws (shell)
  │ python3 - <<'PY'
  │ from pathlib import Path
  │ root = Path('/data/home/skynet/tasks/base/workspaces/zenoh-java/task-75/ze
  │ noh-java/zenoh-java/src')
  │ for path in root.rglob('*.kt'):…
  └ 19 lines...

● Search (grep)
  │ "openSessionWithJsonConfigViaJNI|openSessionWithYamlConfigViaJNI|declareAdva
  │ ncedPublisherViaJNI|declareAdvancedSubscriberViaJNI|serializeViaJNI|deserial
  │ izeViaJNI" in **/*.rs (zenoh-jni/src)
  └ 8 lines found

● Search (grep)
  │ "openSessionWithJsonConfigViaJNI|openSessionWithYamlConfigViaJNI" in **/*.kt
  │ (zenoh-jni-runtime/src)
  └ No matches found

● report_success (MCP: zbobr) · brief: "Review passed: the refactor consistently moves exception cr…
  └ Report stored

Implemented review passed: the refactor consistently moves exception creation to `zenoh-java`, keeps `zenoh-jni-runtime` exception-free, and all checklist items are complete.

--- stderr ---

Changes   +0 -0
Requests  1 Premium (2m 57s)
Tokens    ↑ 956.5k • ↓ 8.6k • 900.1k (cached) • 3.6k (reasoning)
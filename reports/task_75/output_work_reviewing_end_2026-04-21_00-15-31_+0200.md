● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_7"
  └ # Plan: Throw Exceptions from Java (zenoh-java JNI Error Handling Refact...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_30"
  └ ## Summary

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_8"
  └ I reviewed the revised plan in ctx_rec_7 against the current `common-jni...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_28"
  └ # Task Completed

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_29"
  └ Overall assessment: the analog and implementation pattern are good acros...

I’ve got the earlier review context; now I’m checking the actual branch diff and the still-open checklist items to see whether the follow-up fixes really closed the gaps.

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_16"
  └ Create zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt wi...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_13"
  └ publisher.rs:

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_15"
  └ For all JNI adapter Kotlin files in zenoh-jni-runtime:

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_18"
  └ Update all call sites in zenoh-java that call JNI adapter methods:

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_17"
  └ For all JNI call sites in zenoh-java, apply the error-array pattern:

● Inspect branch diff and key patterns (shell)
  │ git --no-pager log --oneline origin/common-jni..HEAD && printf
  │ '\n---DIFFSTAT---\n' && git --no-pager diff --stat
  │ origin/common-jni...HEAD && printf '\n---RUNTIME ZERROR---\n' && rg -n
  │ "ZError|@Throws" zenoh-jni-runtime/src || true && printf '\n---RUST
  │ THROW---\n' && rg -n "throw_exception!|throw_on_jvm|KOTLIN_EXCEPTION_NAME"…
  └ 6 lines...

The follow-up looks promising from the summary, but I want to verify the concrete files rather than trust the status notes—especially the remaining unchecked checklist items.

● Read JNIZenohId.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIZenohId.kt
  └ 29 lines read

● Read ZenohId.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/config/ZenohId.kt
  └ 61 lines read

● Read ZBytesInteropTests.kt
  │ zenoh-jni-runtime/src/jvmTest/kotlin/io/zenoh/ZBytesInteropTests.kt
  └ L1:220 (220 lines read)

● Read ZError.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/exceptions/ZError.kt
  └ 20 lines read

● Read JNISession.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt
  └ L1:260 (260 lines read)

● Read Session.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt
  └ L1:320 (320 lines read)

● Search (grep)
  │ "set_error_string\(|throw_exception!|JObjectArray" in **/*.rs
  │ (zenoh-jni/src)
  └ 125 lines found

● Search (grep)
  │ "arrayOfNulls<String>\(1\)|throw ZError\(|@Throws\(ZError::class\)" in
  │ **/*.kt (zenoh-java/src)
  └ 8 lines found

● Search (grep)
  │ "error: Array<String\?>|@Throws\(|ZError" in **/*.kt (zenoh-jni-runtime/src)
  └ 7 lines found

● List changed files (shell)
  │ git --no-pager diff --name-only origin/common-jni...HEAD
  └ 44 lines...

I’ve confirmed the explicit fixes from the previous failed review. Next I’m spot-checking the remaining high-risk surfaces—liveliness, scouting/open paths, serializer/deserializer, and the runtime wrappers—to decide whether the still-open checklist items are now actually done.

● Read Zenoh.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Zenoh.kt
  └ 154 lines read

● Read Config.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt
  └ 167 lines read

● Read KeyExpr.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/keyexpr/KeyExpr.kt
  └ L1:260 (200 lines read)

● Read Liveliness.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/liveliness/Liveliness.kt
  └ L1:320 (256 lines read)

● Read ZSerializer.kt
  │ zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerializer.kt
  └ 114 lines read

● Read ZDeserializer.kt
  │ zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZDeserializer.kt
  └ 116 lines read

● Read JNIKeyExpr.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIKeyExpr.kt
  └ L1:240 (69 lines read)

● Read JNIScout.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIScout.kt
  └ 58 lines read

● Read JNIConfig.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIConfig.kt
  └ 70 lines read

● Read JNIZBytes.kt
  │ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytes.kt
  └ 35 lines read

● Read JNIZBytesKotlin.kt
  │ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.
  │ kt
  └ L1:220 (49 lines read)

● Read JNILogger.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNILogger.kt
  └ 34 lines read

● Read JNIPublisher.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIPublisher.kt
  └ 40 lines read

● Read JNIQuery.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIQuery.kt
  └ 88 lines read

● Read JNIQuerier.kt
  │ zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIQuerier.kt
  └ 55 lines read

● Search (grep)
  │ "declareLivelinessToken|livelinessGet|declareLivelinessSubscriber|declareAdv
  │ ancedPublisher|declareAdvancedSubscriber|open\(|getPeersZid|getRoutersZid|ge
  │ tZid" (zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt)
  └ 86 lines found

✗ Search (grep)
  │ "@Throws\(ZError::class\)\s*\n\s*fun loadDefault|fun loadDefault\("
  │ (zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt)
  └ rg: the literal "\n" is not allowed in a regex

    Consider enabling multiline mode with the --multiline flag (or -U for
    short).
    When multiline mode is enabled, new line characters can be matched.

● Search (grep)
  │ "declareLivelinessToken|livelinessGet|declareLivelinessSubscriber|declareAdv
  │ ancedPublisher|declareAdvancedSubscriber|open\(|getPeers|getRouters|getZenoh
  │ Id|getZid" in **/*.kt (zenoh-java/src/commonMain/kotlin/io/zenoh)
  └ 8 lines found

● Inspect API diffs (shell)
  │ git --no-pager diff origin/common-jni...HEAD --
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Logger.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Zenoh.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/config/ZenohId.kt | sed -n …
  └ 165 lines...

● Read utils.rs
  │ zenoh-jni/src/utils.rs
  └ L150:220 (37 lines read)

● Read zenoh_id.rs
  │ zenoh-jni/src/zenoh_id.rs
  └ 44 lines read

● Read scouting.rs
  │ zenoh-jni/src/scouting.rs
  └ L1:160 (114 lines read)

● Read errors.rs
  │ zenoh-jni/src/errors.rs
  └ 51 lines read

● Read Logger.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Logger.kt
  └ 39 lines read

● Search (grep)
  │ "JNISession\.open|declarePublisher\(|declareSubscriber\(|declareQuerier\(|de
  │ clareQueryable\(|declareKeyExpr\(|\.put\(|\.delete\(|\.get\(|getPeersZid\(|g
  │ etRoutersZid\(|getZid\(|declareAdvancedPublisher\(|declareAdvancedSubscriber
  │ \(" (zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt)
  └ 8 lines found

I’ve finished the substantive review. Most of the boundary shift is correct now, and the previous ZenohId/ZBytes test blockers are fixed. The remaining issues are narrower: one checklist item is still not fully complete on type specificity in the runtime zbytes adapters, and there’s one public API contract inconsistency in `zenoh-java`.

● check_checklist_item (MCP: zbobr) · id: "ctx_rec_18"
  └ Checklist item ctx_rec_18 checked

● check_checklist_item (MCP: zbobr) · id: "ctx_rec_13"
  └ Checklist item ctx_rec_13 checked

● check_checklist_item (MCP: zbobr) · id: "ctx_rec_17"
  └ Checklist item ctx_rec_17 checked

● check_checklist_item (MCP: zbobr) · id: "ctx_rec_16"
  └ Checklist item ctx_rec_16 checked

● report_failure (MCP: zbobr) · brief: "Review failed: zbytes runtime adapters still use Any? inste…
  └ Report stored

Implemented review result: **failed**.

Main issues:
1. `JNIZBytes.serialize` / `JNIZBytesKotlin.serialize` still return `Any?` instead of the more specific `ByteArray?`, so Phase 4b is not fully complete and downstream code still needs casts.
2. `Config.loadDefault()` now throws `ZError` but is missing `@Throws(ZError::class)`, which regresses the public Java-facing exception contract.

I checked these checklist items as complete: `ctx_rec_13`, `ctx_rec_16`, `ctx_rec_17`, `ctx_rec_18`. I left `ctx_rec_15` unchecked because the runtime zbytes adapter typing is still incomplete.

--- stderr ---

Changes   +0 -0
Requests  1 Premium (2m 52s)
Tokens    ↑ 588.2k • ↓ 9.1k • 530.9k (cached) • 4.6k (reasoning)
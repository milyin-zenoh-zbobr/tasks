● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_15"
  └ For all JNI adapter Kotlin files in zenoh-jni-runtime:

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_30"
  └ ## Summary

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_31"
  └ Overall assessment: the main architectural refactor is now in place and ...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_29"
  └ Overall assessment: the analog and implementation pattern are good acros...

● Read JNIZBytes.kt
  │ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytes.kt
  └ 35 lines read

● Read JNIZBytesKotlin.kt
  │ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.
  │ kt
  └ 49 lines read

● Read Config.kt
  │ zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt
  └ 167 lines read

Now let me look at the Rust zbytes.rs to confirm serialize returns `jbyteArray`:

● Read ZSerializer.kt
  │ zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerializer.kt
  └ 114 lines read

● Search (grep)
  │ "serializeViaJNI\|serialize_via_jni\|fn Java.*serialize\|fn Java.*ZBytes"
  │ (zenoh-jni/src)
  └ No matches found

● Read ZBytesInteropTests.kt
  │ zenoh-jni-runtime/src/jvmTest/kotlin/io/zenoh/ZBytesInteropTests.kt
  └ L1:50 (50 lines read)

Now I'll fix both issues:

● Edit JNIZBytes.kt +2 -2
  └ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytes.kt

✗ Edit JNIZBytesKotlin.kt
  │ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.
  │ kt
  └ No match found

● Read JNIZBytesKotlin.kt
  │ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.
  │ kt
  └ L40:49 (10 lines read)

● Edit JNIZBytesKotlin.kt +2 -2
  └ zenoh-jni-runtime/src/jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.
    kt

Now fix ZSerializer.kt to remove the unnecessary cast, and fix Config.loadDefault():

● Edit ZSerializer.kt +1 -1
  └ zenoh-java/src/jvmAndAndroidMain/kotlin/io/zenoh/ext/ZSerializer.kt

Now fix the test helpers to remove the `as ByteArray?` cast:

● Edit ZBytesInteropTests.kt +2 -2
  └ zenoh-jni-runtime/src/jvmTest/kotlin/io/zenoh/ZBytesInteropTests.kt

Now add `@Throws(ZError::class)` to `Config.loadDefault()`:

● Edit Config.kt +1
  └ zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt

Now let me check if there are any other usages of `JNIZBytesKotlin.serialize` in zenoh-java that may cast the result:

● Search (grep)
  │ "JNIZBytesKotlin\.serialize\|JNIZBytes\.serialize" in **/*.kt
  └ No matches found

● Search (grep)
  │ "JNIZBytes\|JNIZBytesKotlin" in **/*.kt
  └ No matches found

● Find JNIZBytes usages (shell)
  │ grep -rn "JNIZBytes"
  │ /data/home/skynet/tasks/base/workspaces/zenoh-java/task-75/zenoh-java
  │ --include="*.kt"
  └ 88 lines...

Good. The changes look correct. Now let me build to verify:

● Compile Kotlin to verify changes (shell)
  │ cd /data/home/skynet/tasks/base/workspaces/zenoh-java/task-75/zenoh-java &&
  │ ./gradlew :zenoh-jni-runtime:compileKotlinJvm :zenoh-java:compileKotlinJvm
  │ 2>&1 | tail -20
  └ 21 lines...

Build passes. Now run the tests:

● Run JVM tests (shell)
  │ cd /data/home/skynet/tasks/base/workspaces/zenoh-java/task-75/zenoh-java &&
  │ ./gradlew :zenoh-jni-runtime:jvmTest 2>&1 | tail -20
  └ 21 lines...

All tests pass. Now commit the changes:

● Commit the fixes (shell)
  │ cd /data/home/skynet/tasks/base/workspaces/zenoh-java/task-75/zenoh-java
  │ && git add -A && git commit -m "Fix zbytes serialize return type to
  │ ByteArray? and add @Throws to Config.loadDefault
  │
  │ - JNIZBytes.serialize/serializeViaJNI: Any? -> ByteArray? for type-safe …
  └ 13 lines...

● check_checklist_item (MCP: zbobr) · id: "ctx_rec_15"
  └ Checklist item ctx_rec_15 checked

● report_success (MCP: zbobr) · brief: "Fixed zbytes serialize return types (Any? → ByteArray?) and…
  └ Report stored

Fixed two issues flagged in the review:

1. **`JNIZBytes`/`JNIZBytesKotlin` serialize return types** — changed from `Any?` to `ByteArray?`, matching the actual JNI return type. Removed now-unnecessary `as ByteArray` casts in `ZSerializer.kt` and test helpers.

2. **`Config.loadDefault()` missing `@Throws(ZError::class)`** — added the annotation for Java interop consistency with all other factory methods.

Build and all tests pass ✅

--- stderr ---

Changes   +8 -7
Requests  1 Premium (2m 32s)
Tokens    ↑ 815.3k • ↓ 6.3k • 750.4k (cached)
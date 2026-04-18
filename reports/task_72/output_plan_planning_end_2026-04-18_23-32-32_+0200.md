The plan has been submitted. Here's a summary of the key corrections from the previous plan:

1. **Adapter layer preserved, not deleted**: zenoh-kotlin's `io.zenoh.jni.*` classes have two distinct responsibilities — JNI external declarations (bridge to Rust symbols) and domain adapter logic (constructing Publisher, Subscriber, etc.). Only the former is replaced by zenoh-jni-runtime; the adapter logic moves into the domain classes (Session.kt, Config.kt, etc.).

2. **Classpath conflict resolved correctly**: Both zenoh-kotlin and zenoh-jni-runtime define the same class names (e.g., `io.zenoh.jni.JNISession`). The plan explicitly deletes zenoh-kotlin's versions and migrates their adapter logic to domain classes — not just removing the external declarations.

3. **Composite build gated safely**: `includeBuild("zenoh-java")` is gated behind `file("zenoh-java/settings.gradle.kts").exists()`, so ordinary clones without submodule init still work (resolving from Maven Central).

4. **examples/build.gradle.kts included**: The `CompileZenohJNI` Cargo task and `java.library.path` references are explicitly listed for removal.

5. **CI transition honest**: CI still needs Rust (via the submodule's zenoh-jni-runtime build), but it's now zenoh-java's responsibility — the plan notes this and suggests a Maven snapshot alternative for long-term CI simplification.
The plan has been submitted. Here's a summary of what was designed:

## Plan Summary: `zenoh-jni-runtime` Module

**What's already done** in the work branch:
- Rust JNI exports for advanced pub/sub (`ext/` modules)
- Unified `openSessionViaJNI` symbol (removed `00024Companion` prefix)
- `declareAdvancedSubscriberViaJNI` / `declareAdvancedPublisherViaJNI` in session.rs
- zenoh-ext enabled in Cargo.toml

**What needs to be implemented:**

1. **New `zenoh-jni-runtime` Gradle subproject** — owns the Rust native lib build, published as `org.eclipse.zenoh:zenoh-jni-runtime`

2. **Move & refactor JNI Kotlin adapters** to the new module with primitive-only API:
   - Already primitive-only (move as-is): `JNIPublisher`, `JNISubscriber`, `JNIQueryable`, `JNILivelinessToken`, `JNIZBytes`, `JNIZenohId`, all callbacks
   - Require refactoring: `JNISession` (remove facade wrappers), `JNIConfig` (return `Long` not `Config`), `JNIKeyExpr` (return `String` not `KeyExpr`), `JNIQuery`, `JNIQuerier`, `JNIScout`, `JNILiveliness`
   - New adapters: `JNIAdvancedPublisher`, `JNIAdvancedSubscriber`, `JNIMatchingListener`, `JNISampleMissListener` + 2 new callback interfaces

3. **Refactor `zenoh-java`** — delete its `io.zenoh.jni/` source, add runtime dependency, move facade assembly code (Sample/Reply/Publisher construction from raw handles) into `Session.kt` and other facade classes

4. **Move `ZenohLoad`** native library loading from zenoh-java to zenoh-jni-runtime
The revised plan is closer than ctx_rec_1, but it still has blocking architectural issues.

## Blocking issues

1. **The JNI layer is not actually a drop-in replacement**
   The plan’s central claim is that zenoh-kotlin can keep all Kotlin/JNI adapters unchanged and simply swap in zenoh-java’s `libzenoh_jni`. Code inspection contradicts that.

   The clearest example is session opening:
   - In zenoh-kotlin, `JNISession.open` calls an instance native method `openSessionViaJNI`, so the native symbol is `Java_io_zenoh_jni_JNISession_openSessionViaJNI` (`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt:67-73,406`).
   - In zenoh-java, `openSessionViaJNI` lives in the `companion object`, so the native symbol is `Java_io_zenoh_jni_JNISession_00024Companion_openSessionViaJNI` (`zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`; confirmed by `zenoh-java/zenoh-jni/src/session.rs`).

   That alone means zenoh-java’s native library cannot satisfy zenoh-kotlin’s existing `JNISession.open` call without either:
   - changing zenoh-kotlin’s Kotlin JNI declaration, or
   - adding compatibility exports on the zenoh-java native side.

   So the plan’s “byte-for-byte identical JNI signatures” premise is false in a way that blocks even basic session creation.

2. **The plan deletes the code that currently exports advanced JNI entrypoints, while claiming Kotlin stays unchanged**
   The revised plan says to delete `zenoh-jni/src/session.rs` and keep zenoh-kotlin’s Kotlin/JNI layer unchanged.

   But zenoh-kotlin’s unchanged `JNISession.kt` still declares and calls:
   - `declareAdvancedPublisherViaJNI` (`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt:97-128,423`)
   - `declareAdvancedSubscriberViaJNI` (`...:173-205,456`)

   And those JNI exports currently live in `zenoh-jni/src/session.rs`:
   - `Java_io_zenoh_jni_JNISession_declareAdvancedPublisherViaJNI`
   - `Java_io_zenoh_jni_JNISession_declareAdvancedSubscriberViaJNI`

   The corresponding symbols do **not** exist in zenoh-java today (confirmed by repository search and inspection of zenoh-java `zenoh-jni/src/session.rs`).

   So as written, the plan removes the only implementation of advanced declaration entrypoints that zenoh-kotlin still needs.

3. **The two-library Rust boundary is not a sound architectural ABI**
   The plan proposes:
   - base JNI calls handled by zenoh-java’s `libzenoh_jni`
   - advanced JNI calls handled by a separate zenoh-kotlin `libzenoh_kotlin_ext`
   - both sharing the same raw `Session` pointer

   The ext code reconstructs Rust objects from raw pointers using `Arc::from_raw` / `OwnedObject::from_raw` and then calls methods on `zenoh::Session` (`zenoh-jni/src/owned_object.rs`, `zenoh-jni/src/ext/advanced_publisher.rs`, `zenoh-jni/src/session.rs:240-388`).

   That pointer type is a Rust-internal `*const Session`, not a stable C ABI handle. Reusing a pointer created by one independently-built Rust dylib inside another independently-built Rust dylib is not something the plan can treat as “safe as long as versions match”. Matching crate versions may reduce practical risk, but it is not a sound architectural contract.

   Since the user explicitly allows changes in zenoh-java first, the safer direction is to avoid a cross-dylib Rust object boundary entirely.

4. **There is a simpler and safer upstream path that the plan does not choose**
   zenoh-java’s native crate already enables `zenoh-ext` in its default Cargo features (`zenoh-java/zenoh-jni/Cargo.toml`). That makes the current plan’s second ext-only native library look unnecessary.

   The lower-risk architecture is:
   1. Extend zenoh-java’s native library to export the extra JNI entrypoints zenoh-kotlin needs (advanced publisher/subscriber plus any compatibility aliases for symbol-name mismatches such as `JNISession_openSessionViaJNI`).
   2. Keep zenoh-kotlin as the public API/wrapper layer.
   3. Make zenoh-kotlin load and call **one** native library (`zenoh-java`’s), rather than splitting responsibility across two Rust dylibs.

   That avoids the Rust-object-sharing problem and removes most of the loader/resource complexity.

5. **The loader/resource story is under-specified for two libraries**
   Today the JVM loader hardcodes a single target resource path format: `$target/$target.zip` and a single library name search path (`zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Zenoh.kt`). zenoh-java uses the same loader pattern.

   If the architecture truly needs two different native libraries from two artifacts, the plan needs a concrete resource naming/loading strategy that avoids collisions and nondeterministic resolution between identical resource paths coming from different JARs. The plan notices the need for a second library name, but it does not close the loop on how both packaged resources coexist under the current `target/target.zip` lookup scheme.

## Recommendation

Do **not** implement the plan as written.

A sounder plan should be rewritten around this principle:

**zenoh-kotlin keeps its public Kotlin API, but zenoh-java becomes the single native backend after being extended for compatibility.**

At architecture level, that means the plan should explicitly include:
1. Upstream zenoh-java changes to provide the JNI exports zenoh-kotlin requires but zenoh-java does not currently expose.
2. JNI compatibility handling for symbol/name mismatches (the session-open mismatch is already proven).
3. A single-native-library design, or else a deliberate C-ABI bridge between libraries instead of sharing raw Rust `Session` pointers across dylibs.

Until those points are addressed, the worker is likely to implement a migration that compiles partially at best and is unsound at the native boundary.
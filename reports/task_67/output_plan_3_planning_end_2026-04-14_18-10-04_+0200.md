The plan is complete. Here's a summary:

## Verification Result

The zenoh-java PR (`milyin-zenoh-zbobr/zenoh-java#4`, branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`) **contains all necessary JNI code** — nothing is missing.

All 65 JNI symbols zenoh-kotlin needs are present:
- Base symbols (config, key_expr, session, pub/sub, etc.) were already in zenoh-java with identical class/method names
- The PR adds: instance-method `openSessionViaJNI`, `declareAdvancedPublisher/SubscriberViaJNI`, and the full `ext/` module (AdvancedPublisher × 6, AdvancedSubscriber × 5, MatchingListener × 1, SampleMissListener × 1)

## Implementation Plan

The plan to make zenoh-kotlin based on zenoh-java's JNI:

1. **Delete** `zenoh-jni/` Rust crate and `rust-toolchain.toml`
2. **`settings.gradle.kts`**: Remove `include(":zenoh-jni")`
3. **`zenoh-kotlin/build.gradle.kts`**: Replace the Rust build tasks with a `buildZenohJavaNative` task that delegates to a configurable `zenohJavaDir` property (default: `../zenoh-java`); keep the `isRemotePublication`/`jni-libs/` pattern intact for CI
4. **`examples/build.gradle.kts`**: Update `CompileZenohJNI` and library paths to use `{zenohJavaDir}/zenoh-jni/`
5. **CI workflows**: Add a step to checkout zenoh-java's PR branch before building; update Cargo manifest paths accordingly
6. **No changes to `zenoh-kotlin/src/`** — public API preserved entirely
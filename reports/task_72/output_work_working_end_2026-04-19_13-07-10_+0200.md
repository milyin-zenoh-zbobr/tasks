All done. The README now clearly documents both modes:
- **Default**: `gradle jvmTest` uses Maven Central for `zenoh-jni-runtime`, no Rust required
- **Opt-in local**: `gradle jvmTest -Pzenoh.useLocalJniRuntime=true` uses the `zenoh-java` submodule composite build, requires a Rust toolchain
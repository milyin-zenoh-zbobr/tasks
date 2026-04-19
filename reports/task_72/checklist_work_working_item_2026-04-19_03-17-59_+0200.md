ci.yml:
- Add submodules: recursive to actions/checkout step
- Remove zenoh-kotlin's own Rust toolchain setup, cargo fmt/clippy/test/build steps
- Keep Rust toolchain for compiling zenoh-java's zenoh-jni submodule

publish-jvm.yml:
- Remove 6-platform cross-compilation matrix
- Remove all cargo build steps and jni-libs artifact jobs
- Simplify to single ./gradlew publish step

publish-android.yml:
- Remove NDK setup (nttld/setup-ndk)
- Remove rustup target add steps for Android ABIs
- Remove Cargo cross-compilation steps
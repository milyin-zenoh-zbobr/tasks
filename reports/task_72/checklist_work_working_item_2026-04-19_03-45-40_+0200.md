In `.github/workflows/ci.yml`:
- Add `submodules: recursive` to the `actions/checkout@v4` step
- Remove zenoh-kotlin's own Rust toolchain setup steps, `cargo fmt`, `cargo clippy`, `cargo test`, `cargo build` steps (for zenoh-jni)
- Remove `CARGO_TERM_COLOR` env var
- Keep Gradle test

In `.github/workflows/publish-jvm.yml`:
- Remove the 6-platform cross-compilation matrix (builds job) and all `cargo build` steps
- Remove `jni-libs` artifact download/aggregation step
- Add submodules: recursive to checkout
- Simplify to single publish step that calls gradlew directly (no cargo cross-compilation needed)
- Remove `JNI_LIB_PATHS` env var

In `.github/workflows/publish-android.yml`:
- Remove NDK setup (`nttld/setup-ndk`), `rustup target add` steps for Android ABIs, Cargo cross-compilation steps
- Add submodules: recursive to checkout
- Keep the Gradle publish step
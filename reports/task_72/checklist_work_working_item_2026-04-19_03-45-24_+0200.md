In `examples/build.gradle.kts`:
- Remove the `CompileZenohJNI` task registration that runs `cargo build --release --manifest-path ../zenoh-jni/Cargo.toml`
- Remove `dependsOn("CompileZenohJNI")` from example execution tasks
- Remove `-Djava.library.path=../zenoh-jni/target/release` system property from example execution tasks
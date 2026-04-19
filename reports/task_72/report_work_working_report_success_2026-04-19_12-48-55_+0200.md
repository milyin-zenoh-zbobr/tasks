# Review Findings Fixed

## Finding 1: ci/scripts/bump-and-tag.bash broken after deleting zenoh-jni
**Fixed in commit 282130a8**

Removed all zenoh-jni references from the script:
- Removed `cargo +stable install toml-cli` (no longer needed)
- Removed `toml_set_in_place` function
- Removed propagation of version to `zenoh-jni/Cargo.toml`
- Removed the `bump_deps_pattern` block that edited `zenoh-jni/Cargo.toml` and ran `cargo check`
- Removed related variables (`bump_deps_pattern`, `bump_deps_version`, `bump_deps_branch`)
- Simplified the commit to only include `version.txt`

## Finding 2: README.md still documented old JNI/Rust publish flow
**Fixed in commit 282130a8**

Updated three sections:
- **"What you need"**: Removed Rust from prerequisites; added a note that zenoh-kotlin no longer builds its own native JNI and that `zenoh-jni-runtime` is pulled in automatically as a Maven dependency
- **JVM publishing section**: Replaced the "triggers Zenoh-JNI compilation" description with accurate description of depending on `zenoh-jni-runtime`
- **Android publishing section**: Removed NDK/Rust cross-compilation instructions; replaced with accurate description that native binaries come from zenoh-jni-runtime published by zenoh-java
- **Testing section**: Replaced "compiles native library on debug mode" with accurate description using zenoh-java submodule

All checklist items are now complete.
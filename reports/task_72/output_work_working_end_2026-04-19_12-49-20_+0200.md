Both review findings are fixed:

1. **`ci/scripts/bump-and-tag.bash`** — stripped all Cargo/zenoh-jni logic (toml-cli install, `toml_set_in_place`, `BUMP_DEPS_*` variables, the entire dep-bump block). The script now only writes `version.txt` and commits it.

2. **`README.md`** — updated the "What you need", JVM publishing, Android publishing, and testing sections to reflect that zenoh-kotlin now depends on `zenoh-jni-runtime` rather than building its own native library. No Rust toolchain or NDK required.
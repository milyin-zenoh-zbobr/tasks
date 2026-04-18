The plan is ready. Here's a summary of what it covers:

**Goal:** Replace zenoh-kotlin's own Rust/JNI native library with a dependency on `org.eclipse.zenoh:zenoh-jni-runtime` from the zenoh-java project (PR #466, currently open).

**Key steps:**
1. **Phase 0 (Critical):** Verify zenoh-jni-runtime fully covers zenoh-kotlin's JNI surface before making changes — stop and report if not.
2. **Phase 1:** Add zenoh-java as a git submodule pinned to the PR #466 branch.
3. **Phase 2:** Update Gradle — add composite build for local dev, add `zenoh-jni-runtime` dependency, remove all Cargo/Rust build tasks.
4. **Phase 3:** Delete zenoh-kotlin's own `io.zenoh.jni.*` Kotlin wrapper classes and `ZenohLoad` implementations (now provided by zenoh-jni-runtime).
5. **Phase 4:** Delete the entire `zenoh-jni/` Rust directory and `rust-toolchain.toml`.
6. **Phase 5:** Simplify CI/CD workflows — remove native cross-compilation matrix and NDK build steps.
7. **Phase 6:** Verify examples and tests build and pass.

The main risk flagged is a potential circular dependency if zenoh-jni-runtime's JNI classes reference zenoh-kotlin types — Phase 0 resolves this before any destructive changes are made.
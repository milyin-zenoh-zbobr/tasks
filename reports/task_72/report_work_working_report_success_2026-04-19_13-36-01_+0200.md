# Fix: Remove stale Rust crate publishing from release workflow

## Change
Removed the `publish-github` job from `.github/workflows/release.yml` (lines 110-120). That job called `eclipse-zenoh/ci/publish-crates-github@main`, which is a Rust crate publishing action.

## Why
The task removed all of zenoh-kotlin's Rust code (`zenoh-jni/` directory and `rust-toolchain.toml` were deleted in earlier phases). The repo no longer contains any `Cargo.toml` at its root, so this job had nothing to publish and would have failed at release time. Publishing `zenoh-jni-runtime` is zenoh-java's responsibility.

## Commit
`d71cce20` — fix: remove stale publish-crates-github job from release workflow

## Final state
All phases of the migration are now complete:
- zenoh-java added as git submodule (optional local dev mode)
- zenoh-kotlin depends on `zenoh-jni-runtime` via Maven
- All Rust code removed
- Build, CI, and release workflows updated
- ZSerialize/ZDeserialize moved to jvmAndAndroidMain
- Query.acceptsReplies() uses callback-provided value
- Selector params parsing fails fast on error
- settings.gradle.kts fails fast when useLocalJniRuntime=true but submodule absent
- README distinguishes Maven path from local submodule path
- bump-and-tag.bash cleaned of zenoh-jni references
- release.yml no longer publishes Rust crates
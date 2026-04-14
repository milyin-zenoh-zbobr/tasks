# Final Implementation Plan: Make zenoh-kotlin Based on zenoh-java

## Prerequisites

zenoh-java PR #4 (`milyin-zenoh-zbobr/zenoh-java` branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`) is verified complete — all 65 JNI symbols required by zenoh-kotlin are present in that branch. The plan assumes this branch is accessible at `milyin-zenoh-zbobr/zenoh-java`.

## Design Decisions

**Chosen approach:** zenoh-kotlin deletes its own Rust crate entirely and redirects all native-library build steps to zenoh-java's `zenoh-jni` crate. At runtime, zenoh-kotlin bundles the native library produced by zenoh-java's extended crate.

**Rationale:** Single native library at runtime (no cross-library Rust pointer sharing). zenoh-kotlin's full public Kotlin API is preserved. zenoh-java's own API and tests remain unaffected (additive changes to its Rust only). Loader already supports substituting the library source.

**Key analog:** The existing `buildZenohJNI()` function in `zenoh-kotlin/build.gradle.kts` and the `configureCargo()` function are the patterns to update — the pattern stays the same, only the working directory and paths change.

---

## Phase 1: Delete zenoh-kotlin's Rust Crate

- Delete the entire `zenoh-jni/` directory (Rust crate, `Cargo.toml`, `Cargo.lock`, `build.rs`, all `.rs` sources).
- Delete `rust-toolchain.toml` from the repo root. Toolchain is now governed by zenoh-java's own `rust-toolchain.toml` (pinned 1.93.0) when cargo runs from `{zenohJavaDir}/zenoh-jni`.

## Phase 2: `settings.gradle.kts`

Remove this line:
```
include(":zenoh-jni")
```

## Phase 3: `zenoh-kotlin/build.gradle.kts`

**Add** a new property read near the top (after `val isRemotePublication` and `var buildMode`):
```kotlin
val zenohJavaDir = rootProject.findProperty("zenohJavaDir")?.toString() ?: "../zenoh-java"
```

**Update `buildZenohJNI()` function** — this is the fix for blocking issue 1 (toolchain). Change the `project.exec {}` block to:
- Add `workingDir = file("$zenohJavaDir/zenoh-jni")` — this ensures rustup resolves the toolchain from zenoh-java's `rust-toolchain.toml`, not from zenoh-kotlin's cwd.
- Remove `"--manifest-path", "../zenoh-jni/Cargo.toml"` from the commandLine (running from the module directory makes `--manifest-path` redundant).
- The cargo command itself (`"cargo", "build"` with optional `"--release"`) stays the same.

**Update all local-build resource paths** (three places):
1. `jvmMain` non-remote-publication resource srcDir: `"$zenohJavaDir/zenoh-jni/target/$buildMode"` (was `"../zenoh-jni/target/$buildMode"`)
2. `jvmTest` resource srcDir: `"$zenohJavaDir/zenoh-jni/target/$buildMode"` (was `"../zenoh-jni/target/$buildMode"`)
3. `systemProperty("java.library.path", ...)` in the JVM test task: `"$zenohJavaDir/zenoh-jni/target/$buildMode"` (was `"../zenoh-jni/target/$buildMode"`)

**Update `configureCargo()` for Android:**
- `module = "$zenohJavaDir/zenoh-jni"` (was `"../zenoh-jni"`) — the Rust-Android-Gradle plugin runs cargo from the module directory, so zenoh-java's `rust-toolchain.toml` is picked up naturally.
- `targetDirectory = "$zenohJavaDir/zenoh-jni/target/"` (was `"../zenoh-jni/target/"`)

All other content of `build.gradle.kts` (publishing, `configureAndroid()`, `BuildMode` enum, `javadocJar`, dependencies, etc.) remains unchanged.

## Phase 4: `examples/build.gradle.kts`

**Add** at top of file (before `plugins {}` or in the `tasks {}` block, but accessible in the task closures):
```kotlin
val zenohJavaDir = rootProject.findProperty("zenohJavaDir")?.toString() ?: "../zenoh-java"
```

**Update `CompileZenohJNI` task:**
- Add `workingDir = file("$zenohJavaDir/zenoh-jni")` inside the `project.exec {}` block.
- Change commandLine to `("cargo", "build", "--release")` — remove `"--manifest-path", "../zenoh-jni/Cargo.toml"`.

**Update example runner `java.library.path`:**
- Change `"../zenoh-jni/target/release"` → `"$zenohJavaDir/zenoh-jni/target/release"`.

## Phase 5: `.github/workflows/ci.yml` (Blocking Issue 2: CI ownership)

**Decision:** zenoh-kotlin CI stops owning Rust quality gates. zenoh-java owns its own Rust fmt/clippy/test/build pipeline. zenoh-kotlin CI only builds zenoh-java's Rust as a side-effect of running JVM tests via Gradle.

**Remove** all four Rust quality-gate steps from the `build` job:
- `Cargo Format` step (`working-directory: zenoh-jni`, `cargo fmt --all --check`)
- `Clippy Check without Cargo.lock` step
- `Check for feature leaks` step (`cargo test --no-default-features`)
- `Build Zenoh-JNI` step (`cargo build`)

**Remove** the `Install Rust toolchain` step that installs `rustfmt` and `clippy` (no longer needed; the Gradle test task triggers cargo which relies on rustup's default toolchain resolution from zenoh-java's directory).

**Add** checkout of zenoh-java after `uses: actions/checkout@v4`:
```yaml
- name: Checkout zenoh-java
  uses: actions/checkout@v4
  with:
    repository: milyin-zenoh-zbobr/zenoh-java
    ref: zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin
    path: zenoh-java
```

**Add** Rust toolchain setup from zenoh-java's crate (so rustup installs the pinned 1.93.0 toolchain before Gradle test runs cargo):
```yaml
- name: Install Rust toolchain
  working-directory: zenoh-java/zenoh-jni
  run: rustup show
```

**Update `Gradle Test` step** to pass zenohJavaDir pointing at the checked-out directory:
```yaml
- name: Gradle Test
  run: gradle jvmTest --info -PzenohJavaDir=zenoh-java
```
The `path: zenoh-java` checkout places zenoh-java at `$GITHUB_WORKSPACE/zenoh-java`; Gradle resolves `-PzenohJavaDir=zenoh-java` relative to the project root which equals `$GITHUB_WORKSPACE`.

## Phase 6: `.github/workflows/publish-jvm.yml`

In the `builds` job matrix:

**Add** after `Checkout source code`:
```yaml
- name: Checkout zenoh-java
  uses: actions/checkout@v4
  with:
    repository: milyin-zenoh-zbobr/zenoh-java
    ref: zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin
    path: zenoh-java
```

**Update `Install Rust toolchain` step** — add `working-directory` to pick up zenoh-java's pinned toolchain:
```yaml
- name: Install Rust toolchain
  working-directory: zenoh-java/zenoh-jni
  run: |
    rustup show
    rustup target add ${{ matrix.job.target }}
```

**Update `Build` step** — move to zenoh-java's crate directory and remove `--manifest-path`:
```yaml
- name: Build
  working-directory: zenoh-java/zenoh-jni
  run: ${{ matrix.job.build-cmd }} build --release --bins --lib --features=${{ github.event.inputs.features}} --target=${{ matrix.job.target }}
```
Note: `cross` also respects `working-directory`, so cross-compiled targets still work.

**Update `Packaging` step** — change all artifact source paths from `zenoh-jni/target/` to `zenoh-java/zenoh-jni/target/`:
- Linux: `cd "zenoh-java/zenoh-jni/target/${TARGET}/release/"`
- Apple: `cd "zenoh-java/zenoh-jni/target/${TARGET}/release/"`
- Windows: `cd "zenoh-java/zenoh-jni/target/${TARGET}/release/"`

The `publish_jvm_package` job is **unchanged** — it downloads zipped artifacts by name, places them in `jni-libs/`, and publishes with `-PremotePublication=true`.

## Phase 7: `.github/workflows/publish-android.yml`

**Add** checkout of zenoh-java after the first `uses: actions/checkout@v4`:
```yaml
- name: Checkout zenoh-java
  uses: actions/checkout@v4
  with:
    repository: milyin-zenoh-zbobr/zenoh-java
    ref: zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin
    path: zenoh-java
```

**Update `Install Rust toolchain` step** — change to run from zenoh-java's crate directory (toolchain fix; remove `rustfmt`/`clippy` since zenoh-kotlin no longer owns Rust quality gates):
```yaml
- name: Install Rust toolchain
  working-directory: zenoh-java/zenoh-jni
  run: rustup show
```

**Keep** the `Setup Rust toolchains` step (adds Android targets); update it to use `working-directory: zenoh-java/zenoh-jni` so target additions apply to zenoh-java's toolchain context.

**Update** the Gradle publish step to add `-PzenohJavaDir=zenoh-java`:
```yaml
run: ./gradlew publishAndroidReleasePublicationToSonatypeRepository ${{ env.RELEASE }} --info -PremotePublication=true -Pandroid=true ${{ env.PUB_MODE }} -PzenohJavaDir=zenoh-java
```

## Phase 8: `ci/scripts/bump-and-tag.bash` + `release.yml` (Blocking Issue 3: Release automation)

### Decision
zenoh-kotlin stops owning Rust crate versioning and Zenoh dependency version bumps. zenoh-java's own release automation handles Rust dependency management. zenoh-kotlin's release script only manages its own `version.txt`.

### `ci/scripts/bump-and-tag.bash` — Simplify

**Remove entirely:**
- `cargo +stable install toml-cli`
- `function toml_set_in_place() { ... }`
- `toml_set_in_place zenoh-jni/Cargo.toml "package.version" "$version"` line
- The entire `if [[ "$bump_deps_pattern" != '' ]]; then ... fi` block (which bumped zenoh Rust dependency versions and ran `cargo check`)
- `readonly bump_deps_pattern`, `readonly bump_deps_version`, `readonly bump_deps_branch` variable declarations

**Change:**
- `git commit version.txt zenoh-jni/Cargo.toml -m "chore: Bump version to \`$version\`"` → `git commit version.txt -m "chore: Bump version to \`$version\`"`

**Keep** (unchanged): VERSION/LIVE_RUN/GIT_USER_NAME/GIT_USER_EMAIL variable reads, GIT_AUTHOR/COMMITTER exports, `version.txt` write, git tag, git push.

### `release.yml` — Remove Rust dependency management inputs

**Remove** the `zenoh-version` workflow_dispatch input entirely.

**Remove** from the `Bump and tag project` step's `env:` block:
- `BUMP_DEPS_VERSION: ${{ inputs.zenoh-version }}`
- `BUMP_DEPS_PATTERN: ${{ inputs.zenoh-version && 'zenoh.*' || '' }}`
- `BUMP_DEPS_BRANCH: ${{ inputs.zenoh-version && format('release/{0}', inputs.zenoh-version) || '' }}`

The `publish-github` job in `release.yml` uses `eclipse-zenoh/ci/publish-crates-github@main`. Since zenoh-kotlin no longer has a Rust crate to publish to crates.io, this job should be **removed** from `release.yml` (or reviewed — if it only creates GitHub releases, verify whether it still works without a Rust crate; if it tries to publish to crates.io, it must be removed).

---

## Summary of Files Changed

| File | Change |
|---|---|
| `zenoh-jni/` | **Delete entire directory** |
| `rust-toolchain.toml` | **Delete** |
| `settings.gradle.kts` | Remove `include(":zenoh-jni")` |
| `zenoh-kotlin/build.gradle.kts` | Add `zenohJavaDir` property; update `buildZenohJNI()` workingDir (remove --manifest-path); update 3 resource/library paths; update `configureCargo()` module+targetDirectory |
| `examples/build.gradle.kts` | Add `zenohJavaDir`; update `CompileZenohJNI` workingDir + commandLine; update `java.library.path` |
| `.github/workflows/ci.yml` | Remove 4 Rust quality-gate steps + rustfmt/clippy install; add zenoh-java checkout; add Install Rust toolchain (zenoh-java/zenoh-jni workingDir); update Gradle Test (-PzenohJavaDir) |
| `.github/workflows/publish-jvm.yml` | Add zenoh-java checkout; update Install Rust toolchain (workingDir + no rustfmt); update Build step (workingDir, remove --manifest-path); update Packaging step paths |
| `.github/workflows/publish-android.yml` | Add zenoh-java checkout; update Install Rust toolchain (workingDir, remove rustfmt); update Setup Rust toolchains (workingDir); add -PzenohJavaDir to Gradle |
| `ci/scripts/bump-and-tag.bash` | Remove all Rust/TOML management; keep only version.txt bump + git tag/push |
| `.github/workflows/release.yml` | Remove zenoh-version input; remove BUMP_DEPS_* env vars from bump step; remove or review publish-github job |
| `zenoh-kotlin/src/` | **NO CHANGES** |

---

## How This Resolves All Three Blocking Issues

**Blocking Issue 1 (Toolchain):** Every cargo invocation — in Gradle tasks (`buildZenohJNI()`, `CompileZenohJNI`) and in all CI steps (`Build`, `Install Rust toolchain`) — uses `working-directory: zenoh-java/zenoh-jni` or `workingDir = file("$zenohJavaDir/zenoh-jni")`. Rustup resolves the toolchain from zenoh-java's `rust-toolchain.toml`. `rust-toolchain.toml` is deleted from zenoh-kotlin so there's no ambiguity.

**Blocking Issue 2 (CI quality gates):** The four Rust quality-gate steps and their rustfmt/clippy component installs are explicitly removed from zenoh-kotlin's `ci.yml`. zenoh-java owns its own Rust fmt/clippy/test pipeline. zenoh-kotlin's CI only triggers a cargo build as a side-effect of `./gradlew jvmTest` (which calls `buildZenohJni` → `buildZenohJNI()` → cargo from zenoh-java's crate).

**Blocking Issue 3 (Release automation):** `ci/scripts/bump-and-tag.bash` is simplified to only manage `version.txt`. All `zenoh-jni/Cargo.toml` edits, `cargo check`, and `Cargo.lock` commits are removed. `release.yml` inputs for Zenoh dependency bumping (`zenoh-version`, `BUMP_DEPS_*`) are removed since zenoh-kotlin no longer controls its own Rust dependencies.

---

## Verification Steps

1. Clone zenoh-java PR branch to `../zenoh-java` relative to zenoh-kotlin; run `./gradlew :zenoh-kotlin:jvmTest` — all tests pass.
2. Run `./gradlew :examples:ZPub` + `:examples:ZSub` — base pub/sub works.
3. Run `./gradlew :examples:ZAdvancedPublisher` + `:examples:ZAdvancedSubscriber` — ext features work.
4. Confirm `nm -D {libzenoh_jni.so}` shows the instance-method `Java_io_zenoh_jni_JNISession_openSessionViaJNI` symbol.
5. Confirm zenoh-kotlin JAR resources contain native libs from zenoh-java's build output.
6. Confirm no `zenoh-jni/` directory exists in zenoh-kotlin.
7. Confirm `ci/scripts/bump-and-tag.bash` does not reference any Rust/TOML tools.
8. Run `bash -n ci/scripts/bump-and-tag.bash` — script syntax is valid.
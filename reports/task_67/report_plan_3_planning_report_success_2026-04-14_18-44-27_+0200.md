# Final Implementation Plan: Make zenoh-kotlin Based on zenoh-java

## Prerequisites

zenoh-java PR #4 (`milyin-zenoh-zbobr/zenoh-java` branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`) is verified complete — all JNI symbols required by zenoh-kotlin are present in that branch. The plan assumes this branch is accessible at `milyin-zenoh-zbobr/zenoh-java`.

## Design Decisions

**Chosen approach:** zenoh-kotlin deletes its own Rust crate entirely and redirects all native-library build steps to zenoh-java's `zenoh-jni` crate. At runtime, zenoh-kotlin bundles the native library produced by zenoh-java's extended crate.

**Rationale:** Single native library at runtime. zenoh-kotlin's full public Kotlin API is preserved. zenoh-java's own API and tests remain unaffected. Loader already supports substituting the library source.

**Key analog:** The existing `buildZenohJNI()` function and `configureCargo()` in `zenoh-kotlin/build.gradle.kts` — the pattern stays the same, only the working directory and paths change.

**CRITICAL path semantics (fixes Blocking Issue 1):** All uses of `zenohJavaDir` in Gradle files MUST use `rootProject.file(zenohJavaDir)` to get an absolute `File` object. This resolves the path relative to the **repository root**, regardless of which subproject file is executing. Never use the raw `zenohJavaDir` string directly in `file()`, `srcDir()`, `module`, or `workingDir` — always go through `rootProject.file(zenohJavaDir)` first.

---

## Phase 1: Delete zenoh-kotlin's Rust Crate

- Delete the entire `zenoh-jni/` directory (Rust crate, `Cargo.toml`, `Cargo.lock`, `build.rs`, all `.rs` sources).
- Delete `rust-toolchain.toml` from the repo root. Toolchain is now governed by zenoh-java's own `rust-toolchain.toml` (pinned 1.93.0) when cargo runs from zenoh-java's `zenoh-jni` directory.

## Phase 2: `settings.gradle.kts`

Remove the line:
```
include(":zenoh-jni")
```

## Phase 3: `zenoh-kotlin/build.gradle.kts`

**Add** a property read near the top (after `val isRemotePublication` and `var buildMode`):
```kotlin
val zenohJavaDir = rootProject.findProperty("zenohJavaDir")?.toString() ?: "../zenoh-java"
val zenohJniAbsDir = rootProject.file(zenohJavaDir).resolve("zenoh-jni")
```

`zenohJniAbsDir` is now an absolute `java.io.File` pointing to zenoh-java's `zenoh-jni` directory, resolved from the repository root. All subsequent uses go through this variable.

**Update `buildZenohJNI()` function** — the function signature and behavior stay the same, but:
- **Change the `project.exec {}` block** to use `workingDir = zenohJniAbsDir` (passed in as a parameter or captured from outer scope). Remove `"--manifest-path", "../zenoh-jni/Cargo.toml"` from the commandLine entirely (running from the module directory makes it redundant). The cargo command becomes:
  ```kotlin
  project.exec {
      workingDir = zenohJniAbsDir
      commandLine(*(cargoCommand.toTypedArray()))
  }
  ```
- This ensures rustup resolves the toolchain from zenoh-java's `rust-toolchain.toml`.

**Update all local-build resource paths** (three places):
1. `jvmMain` non-remote-publication `resources.srcDir`: `zenohJniAbsDir.resolve("target/$buildMode")` (was `"../zenoh-jni/target/$buildMode"`)
2. `jvmTest` `resources.srcDir`: `zenohJniAbsDir.resolve("target/$buildMode")` (was `"../zenoh-jni/target/$buildMode"`)
3. `systemProperty("java.library.path", ...)` in the JVM test task: `zenohJniAbsDir.resolve("target/$buildMode").absolutePath` (was `"../zenoh-jni/target/$buildMode"`)

**Update `configureCargo()` for Android:**
- `module = zenohJniAbsDir.absolutePath` (was `"../zenoh-jni"`) — the Rust-Android-Gradle plugin runs cargo from the module directory, so zenoh-java's `rust-toolchain.toml` is picked up naturally.
- `targetDirectory = zenohJniAbsDir.resolve("target").absolutePath` (was `"../zenoh-jni/target/"`)

Note: `zenohJniAbsDir` must be passed into `configureCargo()` or captured from the enclosing scope, since it is defined at project level.

All other content of `build.gradle.kts` remains unchanged.

## Phase 4: `examples/build.gradle.kts`

**Add** at the top of the `tasks {}` block (or as a project-level property):
```kotlin
val zenohJavaDir = rootProject.findProperty("zenohJavaDir")?.toString() ?: "../zenoh-java"
val zenohJniAbsDir = rootProject.file(zenohJavaDir).resolve("zenoh-jni")
```

**Update `CompileZenohJNI` task:**
```kotlin
tasks.register("CompileZenohJNI") {
    project.exec {
        workingDir = zenohJniAbsDir
        commandLine("cargo", "build", "--release")
    }
}
```
Remove `"--manifest-path", "../zenoh-jni/Cargo.toml"` entirely.

**Update example runner `java.library.path`:**
```kotlin
val zenohPaths = zenohJniAbsDir.resolve("target/release").absolutePath
```
(was `"../zenoh-jni/target/release"`)

## Phase 5: `.github/workflows/ci.yml`

**Decision:** zenoh-kotlin CI stops owning Rust quality gates. zenoh-java owns its own Rust fmt/clippy/test/build pipeline. zenoh-kotlin CI only triggers cargo indirectly via Gradle's `buildZenohJni` task during JVM tests.

**Remove** these steps from the `build` job:
- `Cargo Format` step
- `Clippy Check without Cargo.lock` step
- `Check for feature leaks` step
- `Build Zenoh-JNI` step

**Replace** the `Install Rust toolchain` step (which installed rustfmt/clippy) with a simpler one that just activates zenoh-java's pinned toolchain:
```yaml
- name: Install Rust toolchain
  working-directory: zenoh-java/zenoh-jni
  run: rustup show
```

**Add** checkout of zenoh-java immediately after `uses: actions/checkout@v4`:
```yaml
- name: Checkout zenoh-java
  uses: actions/checkout@v4
  with:
    repository: milyin-zenoh-zbobr/zenoh-java
    ref: zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin
    path: zenoh-java
```

**Update `Gradle Test` step** to pass `zenohJavaDir`:
```yaml
- name: Gradle Test
  run: gradle jvmTest --info -PzenohJavaDir=zenoh-java
```
The `-PzenohJavaDir=zenoh-java` value is relative to the repository root (which is `$GITHUB_WORKSPACE`). Gradle resolves it with `rootProject.file("zenoh-java")` → absolute path `$GITHUB_WORKSPACE/zenoh-java`. Correct.

## Phase 6: `.github/workflows/publish-jvm.yml`

In the `builds` job:

**Add** after `Checkout source code`:
```yaml
- name: Checkout zenoh-java
  uses: actions/checkout@v4
  with:
    repository: milyin-zenoh-zbobr/zenoh-java
    ref: zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin
    path: zenoh-java
```

**Replace `Install Rust toolchain` step** — run from zenoh-java's crate directory, no longer installing rustfmt/clippy:
```yaml
- name: Install Rust toolchain
  working-directory: zenoh-java/zenoh-jni
  run: |
    rustup show
    rustup target add ${{ matrix.job.target }}
```

**Update `Build` step** — run from zenoh-java's crate directory, remove `--manifest-path`:
```yaml
- name: Build
  working-directory: zenoh-java/zenoh-jni
  run: ${{ matrix.job.build-cmd }} build --release --bins --lib --features=${{ github.event.inputs.features}} --target=${{ matrix.job.target }}
```
`cross` also respects `working-directory`.

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

**Replace `Install Rust toolchain` step** — change to run from zenoh-java's crate directory, remove `rustfmt`/`clippy` installation:
```yaml
- name: Install Rust toolchain
  working-directory: zenoh-java/zenoh-jni
  run: rustup show
```

**Update `Setup Rust toolchains` step** to also use zenoh-java's working directory (so toolchain additions apply in that context):
```yaml
- name: Setup Rust toolchains
  working-directory: zenoh-java/zenoh-jni
  run: |
    rustup target add armv7-linux-androideabi
    rustup target add i686-linux-android
    rustup target add aarch64-linux-android
    rustup target add x86_64-linux-android
```

**Update the Gradle publish step** to add `-PzenohJavaDir=zenoh-java`:
```yaml
run: ./gradlew publishAndroidReleasePublicationToSonatypeRepository ${{ env.RELEASE }} --info -PremotePublication=true -Pandroid=true ${{ env.PUB_MODE }} -PzenohJavaDir=zenoh-java
```

## Phase 8: `ci/scripts/bump-and-tag.bash` + `release.yml`

### Decision
zenoh-kotlin stops owning Rust crate versioning and Zenoh dependency version bumps. zenoh-java's own release automation handles Rust dependency management. zenoh-kotlin's release script only manages its own `version.txt`.

### `ci/scripts/bump-and-tag.bash` — Simplify

**Remove entirely:**
- `cargo +stable install toml-cli`
- `function toml_set_in_place() { ... }`
- `toml_set_in_place zenoh-jni/Cargo.toml "package.version" "$version"` line
- The entire `if [[ "$bump_deps_pattern" != '' ]]; then ... fi` block
- `readonly bump_deps_pattern`, `readonly bump_deps_version`, `readonly bump_deps_branch` variable declarations at the top

**Change:**
- `git commit version.txt zenoh-jni/Cargo.toml -m "..."` → `git commit version.txt -m "chore: Bump version to \`$version\`"`

**Keep** (unchanged): VERSION/LIVE_RUN/GIT_USER_NAME/GIT_USER_EMAIL variable reads, GIT_AUTHOR/COMMITTER exports, `version.txt` write, git tag, git push.

### `release.yml` — Remove Rust dependency management inputs

**Remove** the `zenoh-version` workflow_dispatch input entirely.

**Remove** from the `Bump and tag project` step's `env:` block:
- `BUMP_DEPS_VERSION: ${{ inputs.zenoh-version }}`
- `BUMP_DEPS_PATTERN: ${{ inputs.zenoh-version && 'zenoh.*' || '' }}`
- `BUMP_DEPS_BRANCH: ${{ inputs.zenoh-version && format('release/{0}', inputs.zenoh-version) || '' }}`

**Remove the `publish-github` job entirely.** The `eclipse-zenoh/ci/publish-crates-github@main` action is named for and designed around Rust crates (crates.io publishing + GitHub release for crate-based projects). zenoh-kotlin is a pure Kotlin library with no Rust crate to publish. This job has no valid role after the migration and must be removed to avoid failed release runs.

---

## Summary of Files Changed

| File | Change |
|---|---|
| `zenoh-jni/` | **Delete entire directory** |
| `rust-toolchain.toml` | **Delete** |
| `settings.gradle.kts` | Remove `include(":zenoh-jni")` |
| `zenoh-kotlin/build.gradle.kts` | Add `zenohJavaDir` + `zenohJniAbsDir = rootProject.file(zenohJavaDir).resolve("zenoh-jni")`; update `buildZenohJNI()` workingDir; update 3 resource/library paths via `zenohJniAbsDir`; update `configureCargo()` module+targetDirectory |
| `examples/build.gradle.kts` | Add `zenohJavaDir` + `zenohJniAbsDir`; update `CompileZenohJNI` workingDir; update `java.library.path` |
| `.github/workflows/ci.yml` | Remove 4 Rust quality-gate steps; replace Install Rust toolchain (use zenoh-java/zenoh-jni workingDir, no rustfmt/clippy); add zenoh-java checkout; pass -PzenohJavaDir=zenoh-java to Gradle Test |
| `.github/workflows/publish-jvm.yml` | Add zenoh-java checkout; replace Install Rust toolchain (workingDir zenoh-java/zenoh-jni, no rustfmt); update Build step (workingDir, no --manifest-path); update Packaging paths to zenoh-java/zenoh-jni/target |
| `.github/workflows/publish-android.yml` | Add zenoh-java checkout; replace Install Rust toolchain (workingDir zenoh-java/zenoh-jni, no rustfmt/clippy); update Setup Rust toolchains (workingDir); add -PzenohJavaDir=zenoh-java to Gradle |
| `ci/scripts/bump-and-tag.bash` | Remove all Rust/TOML management; git commit only version.txt |
| `.github/workflows/release.yml` | Remove zenoh-version input; remove BUMP_DEPS_* env vars; **remove publish-github job entirely** |
| `zenoh-kotlin/src/` | **NO CHANGES** |

---

## How This Resolves Both Blocking Issues from ctx_rec_13

**Blocking Issue 1 (`zenohJavaDir` path semantics):** Every Gradle path is computed via `rootProject.file(zenohJavaDir).resolve("zenoh-jni")`, producing an absolute path independent of which subproject is executing. CI passes `-PzenohJavaDir=zenoh-java` (repo-root-relative), and `rootProject.file("zenoh-java")` resolves it to `$GITHUB_WORKSPACE/zenoh-java`. Local dev checks out zenoh-java at `../zenoh-java` (parent of repo root), which is also correctly resolved by `rootProject.file("../zenoh-java")`. The convention is consistent everywhere.

**Blocking Issue 2 (`publish-github` job):** The job is **explicitly removed**. The `eclipse-zenoh/ci/publish-crates-github@main` action is Rust-crate-oriented. zenoh-kotlin is a pure Kotlin library after this migration — there is no crate to publish to crates.io, and no crate-based GitHub release to cut. Removing this job is the correct architectural decision.

---

## Verification Steps

1. Clone zenoh-java PR branch to `../zenoh-java` relative to zenoh-kotlin repo root; run `./gradlew :zenoh-kotlin:jvmTest` — all tests pass.
2. Run `./gradlew :examples:ZPub` and `:examples:ZSub` — basic pub/sub works.
3. Confirm no `zenoh-jni/` directory exists in zenoh-kotlin repo.
4. Confirm `ci/scripts/bump-and-tag.bash` references no Rust/TOML tools; `bash -n ci/scripts/bump-and-tag.bash` passes.
5. Confirm `release.yml` has no `zenoh-version` input and no `publish-github` job.
6. Confirm zenoh-kotlin JAR resources contain native libs from zenoh-java's build output (check jar contents after test run).
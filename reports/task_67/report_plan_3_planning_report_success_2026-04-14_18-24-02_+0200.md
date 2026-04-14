# Revised Implementation Plan: Make zenoh-kotlin Based on zenoh-java

## Background

Previous plan (ctx_rec_8) had the right direction but two blocking architectural gaps identified in adversarial review (ctx_rec_9):

1. **Toolchain gap**: When running `cargo build --manifest-path {zenohJavaDir}/zenoh-jni/Cargo.toml` from zenoh-kotlin's cwd (no `rust-toolchain.toml` after deletion), rustup resolves the toolchain from cwd, NOT from zenoh-java's `rust-toolchain.toml`. Fix: explicitly set `workingDir = {zenohJavaDir}/zenoh-jni` for all cargo invocations.

2. **CI ownership gap**: `ci.yml` runs cargo fmt/clippy/test/build in `zenoh-jni/`. After deletion, the plan must explicitly decide: zenoh-kotlin CI **removes** those Rust quality gates; zenoh-java owns its own Rust CI pipeline. zenoh-kotlin CI only builds zenoh-java's Rust as a prerequisite for JVM tests.

## Prerequisite

zenoh-java PR #4 (`milyin-zenoh-zbobr/zenoh-java` branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`) is verified complete — all 65 required JNI symbols are present. This branch must be checked out at `../zenoh-java` locally or fetched by CI.

## Kotlin Source — Zero Changes

All files under `zenoh-kotlin/src/` are completely preserved throughout. Public API unchanged.

---

## Phase 1: Delete zenoh-kotlin's Rust Crate

- Delete the entire `zenoh-jni/` directory (Rust crate, `Cargo.toml`, `Cargo.lock`, `build.rs`, all `.rs` sources).
- Delete `rust-toolchain.toml` from the repo root. Toolchain is now governed by zenoh-java's own `rust-toolchain.toml` (pinned to 1.93.0) whenever cargo is invoked from `{zenohJavaDir}/zenoh-jni`.

## Phase 2: Update `settings.gradle.kts`

Remove the line:
```
include(":zenoh-jni")
```

## Phase 3: Update `zenoh-kotlin/build.gradle.kts`

**Add** at the top (after existing property reads):
```kotlin
val zenohJavaDir = rootProject.findProperty("zenohJavaDir")?.toString() ?: "../zenoh-java"
```

**Update `buildZenohJNI()` function:**
- Set `workingDir = file("$zenohJavaDir/zenoh-jni")` on the `project.exec {}` block (this is the key fix for blocking issue 1).
- Drop `"--manifest-path", "../zenoh-jni/Cargo.toml"` from the commandLine (running from the module directory makes `--manifest-path` redundant).

**Update all local-build resource paths** (3 places):
- `jvmMain` non-remote-publication resource: `"$zenohJavaDir/zenoh-jni/target/$buildMode"`
- `jvmTest` resource (if separate): same substitution
- `systemProperty("java.library.path", ...)` in test task: `"$zenohJavaDir/zenoh-jni/target/$buildMode"`

**Update `configureCargo()` for Android:**
- `module = "$zenohJavaDir/zenoh-jni"` — the Rust-Android-Gradle plugin runs cargo from the module directory, so it will pick up zenoh-java's `rust-toolchain.toml` naturally.
- `targetDirectory = "$zenohJavaDir/zenoh-jni/target/"`

## Phase 4: Update `examples/build.gradle.kts`

**Add** at top of file:
```kotlin
val zenohJavaDir = rootProject.findProperty("zenohJavaDir")?.toString() ?: "../zenoh-java"
```

**Update `CompileZenohJNI` task:**
- Add `workingDir = file("$zenohJavaDir/zenoh-jni")`
- Change commandLine to `("cargo", "build", "--release")` (no more `--manifest-path`)

**Update example runner `java.library.path`:**
- `"$zenohJavaDir/zenoh-jni/target/release"`

## Phase 5: Update `.github/workflows/ci.yml` (Blocking Issue 2 fix)

**Remove entirely** from the `build` job (these are zenoh-java's Rust quality gates, not zenoh-kotlin's):
- `Cargo Format` step (`working-directory: zenoh-jni`)
- `Clippy Check without Cargo.lock` step
- `Check for feature leaks` step
- `Build Zenoh-JNI` step

**Add** a new step immediately after `uses: actions/checkout@v4`:
```yaml
- name: Checkout zenoh-java
  uses: actions/checkout@v4
  with:
    repository: milyin-zenoh-zbobr/zenoh-java
    ref: zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin
    path: zenoh-java
```

**Update `Install Rust toolchain` step** to run from zenoh-java's crate directory, ensuring the pinned toolchain from zenoh-java's `rust-toolchain.toml` is installed (blocking issue 1 fix for CI):
```yaml
- name: Install Rust toolchain
  working-directory: zenoh-java/zenoh-jni
  run: |
    rustup show
    rustup component add rustfmt clippy
```

**Update `Gradle Test` step** to pass the zenoh-java location:
```yaml
- name: Gradle Test
  run: gradle jvmTest --info -PzenohJavaDir=zenoh-java
```

The `path: zenoh-java` checkout puts zenoh-java at `$GITHUB_WORKSPACE/zenoh-java`, which aligns with `-PzenohJavaDir=zenoh-java` (Gradle resolves relative paths from the project root, which equals `$GITHUB_WORKSPACE`).

## Phase 6: Update `.github/workflows/publish-jvm.yml`

In the `builds` job:

**Add step** immediately after `Checkout source code`:
```yaml
- name: Checkout zenoh-java
  uses: actions/checkout@v4
  with:
    repository: milyin-zenoh-zbobr/zenoh-java
    ref: zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin
    path: zenoh-java
```

**Update `Install Rust toolchain` step** — run from zenoh-java's crate to pick up its pinned toolchain:
```yaml
- name: Install Rust toolchain
  working-directory: zenoh-java/zenoh-jni
  run: |
    rustup show
    rustup target add ${{ matrix.job.target }}
```

**Update `Build` step** — run from zenoh-java's crate directory (key fix):
```yaml
- name: Build
  working-directory: zenoh-java/zenoh-jni
  run: ${{ matrix.job.build-cmd }} build --release --bins --lib --features=${{ github.event.inputs.features}} --target=${{ matrix.job.target }}
```
(Cross compilation tools like `cross` still work with `working-directory` set.)

**Update `Packaging` step** — change artifact source paths from `zenoh-jni/target/` to `zenoh-java/zenoh-jni/target/`:
- For linux: `cd "zenoh-java/zenoh-jni/target/${TARGET}/release/"`
- For apple: same substitution
- For windows: same substitution

The `publish` job is **unchanged** — it downloads zip artifacts by name from `builds`, places them in `jni-libs/`, and runs Gradle with `-PremotePublication=true` (which uses the `jni-libs/` path, not `zenoh-jni/target/`).

## Phase 7: Update `.github/workflows/publish-android.yml`

**Add step** after the first `uses: actions/checkout@v4`:
```yaml
- name: Checkout zenoh-java
  uses: actions/checkout@v4
  with:
    repository: milyin-zenoh-zbobr/zenoh-java
    ref: zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin
    path: zenoh-java
```

**Update `Install Rust toolchain` step:**
```yaml
- name: Install Rust toolchain
  working-directory: zenoh-java/zenoh-jni
  run: |
    rustup show
    rustup component add rustfmt clippy
```

**Update Gradle publish step** — add `-PzenohJavaDir=zenoh-java`:
```yaml
run: ./gradlew publishAndroidReleasePublicationToSonatypeRepository ${{ env.RELEASE }} --info -PremotePublication=true -Pandroid=true ${{ env.PUB_MODE }} -PzenohJavaDir=zenoh-java
```

## Summary of Files Changed

| File | Change |
|---|---|
| `zenoh-jni/` | **Delete entire directory** |
| `rust-toolchain.toml` | **Delete** |
| `settings.gradle.kts` | Remove `include(":zenoh-jni")` |
| `zenoh-kotlin/build.gradle.kts` | Add `zenohJavaDir` property; update `buildZenohJNI()` workingDir + remove `--manifest-path`; update resource/library paths; update `configureCargo()` |
| `examples/build.gradle.kts` | Add `zenohJavaDir`; update `CompileZenohJNI` workingDir; update `java.library.path` |
| `.github/workflows/ci.yml` | Remove 4 Rust quality-gate steps; add zenoh-java checkout; update Install Rust toolchain (workingDir); update Gradle Test (pass -PzenohJavaDir) |
| `.github/workflows/publish-jvm.yml` | Add zenoh-java checkout; update Install Rust toolchain (workingDir); update Build step (workingDir); update Packaging paths |
| `.github/workflows/publish-android.yml` | Add zenoh-java checkout; update Install Rust toolchain; add -PzenohJavaDir to Gradle |
| `zenoh-kotlin/src/` | **NO CHANGES** |

## How This Resolves Both Blocking Issues

**Blocking Issue 1 (Toolchain):** Every cargo invocation — in Gradle tasks (`buildZenohJNI()`, `CompileZenohJNI`) and in all CI steps (`Build`, `Install Rust toolchain`) — uses `working-directory: zenoh-java/zenoh-jni` (or `workingDir = file("$zenohJavaDir/zenoh-jni")` in Gradle). This ensures rustup/cargo resolution uses zenoh-java's `rust-toolchain.toml`. The Android Gradle plugin's `module` setting also runs cargo from that directory, so it gets the same treatment.

**Blocking Issue 2 (CI ownership):** The four Rust quality-gate steps (fmt, clippy, no-default-features, build) are explicitly removed from zenoh-kotlin's `ci.yml`. zenoh-java owns its own Rust quality pipeline. zenoh-kotlin's CI only triggers a cargo build as a side-effect of running JVM tests via Gradle (which calls `buildZenohJni` → `buildZenohJNI()` → cargo from zenoh-java's crate).

## Verification Steps

1. Locally: clone zenoh-java PR branch to `../zenoh-java` relative to zenoh-kotlin; run `./gradlew :zenoh-kotlin:jvmTest` — all tests pass
2. Locally: `./gradlew :examples:ZPub` + `:examples:ZSub` — base pub/sub works
3. Locally: `./gradlew :examples:ZAdvancedPublisher` + `:examples:ZAdvancedSubscriber` — ext features work
4. Confirm `nm -D {libzenoh_jni.so path} | grep openSessionViaJNI` shows instance-method variant
5. Confirm zenoh-kotlin JAR resources contain native libs from zenoh-java's build output
6. Confirm no `zenoh-jni/` directory exists in zenoh-kotlin after deletion

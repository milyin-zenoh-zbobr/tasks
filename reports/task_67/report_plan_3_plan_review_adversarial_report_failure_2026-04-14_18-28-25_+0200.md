I reviewed the revised plan against the current zenoh-kotlin repository and its active build/release wiring.

## Verdict
The high-level direction is still correct:
- reusing zenoh-java’s `zenoh-jni` is consistent with the current Gradle/runtime model,
- keeping `zenoh-kotlin/src/` unchanged is plausible,
- and I did not find evidence that zenoh-java PR #4 is missing JNI needed by zenoh-kotlin.

However, the plan is **not yet implementation-ready** because it omits an active part of the repository that will definitely break after deleting `zenoh-jni/`.

## Blocking issue: release/versioning automation still owns `zenoh-jni`
The plan covers local builds, examples, CI, and publish workflows, but it does **not** cover the release automation that still edits and validates `zenoh-jni/Cargo.toml` directly.

### Evidence
1. `ci/scripts/bump-and-tag.bash` actively mutates zenoh-kotlin’s in-repo Rust crate:
   - `toml_set_in_place zenoh-jni/Cargo.toml "package.version" "$version"` (line 37)
   - commits `version.txt zenoh-jni/Cargo.toml` (line 39)
   - reads and rewrites Rust dependencies in `zenoh-jni/Cargo.toml` (lines 43, 46, 50)
   - runs `cargo check --manifest-path zenoh-jni/Cargo.toml` (line 54)
   - commits `zenoh-jni/Cargo.toml zenoh-jni/Cargo.lock` (line 57)

2. `.github/workflows/release.yml` actually invokes that script today:
   - `run: bash ci/scripts/bump-and-tag.bash` (line 66)

So if the implementation follows the current plan and deletes `zenoh-jni/`, the release workflow will fail immediately, even if normal CI and publishing are fixed.

## Why this is architectural, not a minor cleanup
This is not just a stray path replacement. The migration changes **ownership** of the Rust crate and its dependency/version management.

Today zenoh-kotlin release automation assumes:
- this repo owns a Rust crate,
- this repo bumps that crate’s version together with `version.txt`,
- this repo optionally bumps zenoh Rust dependencies/branches before release.

After the migration, those assumptions are false. zenoh-kotlin no longer owns `Cargo.toml`, `Cargo.lock`, or Rust dependency selection. That means the release process must be redesigned, not merely path-updated.

## What the plan needs to say explicitly
Before implementation starts, the plan should add a release-automation section that makes one architecture choice explicit:

1. **Recommended:** zenoh-kotlin stops owning Rust version/dependency bumps.
   - Update `ci/scripts/bump-and-tag.bash` to only manage zenoh-kotlin’s own release data (at minimum `version.txt`), and remove all `zenoh-jni/Cargo.toml` / `Cargo.lock` edits and checks.
   - Revisit `release.yml` inputs `zenoh-version` / `BUMP_DEPS_*`: either remove them, or redefine them to select a zenoh-java ref/tag used by checkout steps instead of mutating a deleted local crate.

2. Less likely alternative: zenoh-kotlin release automation intentionally coordinates zenoh-java releases too.
   - If that is intended, the plan must describe how an external repo is checked out, mutated, committed, and versioned safely. Nothing in the current plan addresses that, and it would be a much larger architectural change.

Without this explicit decision, a worker could implement the plan exactly as written and still leave the repository unable to cut releases.

## Non-blocking observations
- The README will need updating because it still tells users zenoh-kotlin compiles its own in-repo JNI (`README.md`, build/test sections).
- `publish-android.yml` and `ci.yml` can likely drop `rustfmt`/`clippy` component installation once zenoh-kotlin stops owning Rust quality gates, though that is cleanup rather than a blocker.

## Bottom line
The plan is close, but I would send it back for one more revision.

**Required revision:** extend the plan to cover `.github/workflows/release.yml` and `ci/scripts/bump-and-tag.bash`, and explicitly define post-migration ownership of Rust crate versioning/dependency bumps. Until that is specified, the migration plan is incomplete in a way that will break the repository’s release path.
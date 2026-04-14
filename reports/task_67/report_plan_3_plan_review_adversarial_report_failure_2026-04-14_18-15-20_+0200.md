I reviewed the proposed plan against the current zenoh-kotlin repository layout and the referenced zenoh-java branch `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`.

## Verdict
The overall direction is right: reusing zenoh-java’s `zenoh-jni` and keeping zenoh-kotlin’s Kotlin API/JNI class surface intact is consistent with the codebase, and I did not find evidence that PR #4 is still missing required JNI entry points.

However, I do **not** think the plan is implementation-ready yet. There are **two blocking architectural gaps** that should be fixed in the plan before coding starts.

## What checks out
1. **The current zenoh-kotlin build really is centered on an in-repo Rust crate.**
   - `settings.gradle.kts` includes `:zenoh-jni`.
   - `zenoh-kotlin/build.gradle.kts` builds `../zenoh-jni/Cargo.toml`, consumes `../zenoh-jni/target/$buildMode`, and wires Android cargo builds through `module = "../zenoh-jni"`.
   - `examples/build.gradle.kts` also builds and loads `../zenoh-jni`.
   So the plan is looking in the right places.

2. **The runtime loader supports this migration model.**
   - On JVM, `src/jvmMain/kotlin/io/zenoh/Zenoh.kt` loads either unpacked local native libraries (`libzenoh_jni.*`) or packaged zipped artifacts from resources.
   - That means pointing the build to zenoh-java’s produced `libzenoh_jni` artifacts is a good fit; no Kotlin API rewrite is inherently required.

3. **The zenoh-java branch layout matches the plan’s core assumption.**
   - The referenced branch has a top-level `zenoh-jni/` crate and its own `rust-toolchain.toml`.

## Blocking issue 1: the plan breaks toolchain selection for external cargo builds
The plan says to delete zenoh-kotlin’s `rust-toolchain.toml` and invoke cargo with `--manifest-path {zenohJavaDir}/zenoh-jni/Cargo.toml`.

That is not enough.

`zenoh-kotlin/build.gradle.kts` currently runs cargo from the Gradle project directory. If implementation keeps that pattern and only swaps `--manifest-path`, then rustup toolchain resolution will be driven by the **current working directory / current repo**, not automatically by the manifest path inside `zenoh-java/`.

Today both repos happen to pin Rust 1.93.0, but deleting zenoh-kotlin’s `rust-toolchain.toml` would make local and CI builds depend on the ambient/default toolchain unless the worker explicitly compensates for it.

### Why this matters
This is exactly the kind of hidden build drift that will make local builds and CI behave differently, especially once zenoh-java moves its pinned toolchain independently.

### What the revised plan should require
The plan needs to say one of these explicitly:
1. **Run cargo with `workingDir` inside the checked-out zenoh-java repo** (preferred), so zenoh-java’s own `rust-toolchain.toml` governs the build.
2. Or **keep a matching `rust-toolchain.toml` in zenoh-kotlin** and accept the coupling.
3. Or **delegate native building to zenoh-java’s own build entrypoint** instead of calling cargo directly from zenoh-kotlin.

Without one of those, the current plan is underspecified in a way that can produce the wrong implementation.

## Blocking issue 2: zenoh-kotlin CI ownership of Rust checks is unresolved
The plan says, for `ci.yml`, to “apply same changes if it runs a native build.” That is too vague for the actual workflow.

Current `ci.yml` does not merely build a native artifact. It explicitly runs:
- `cargo fmt --all --check`
- `cargo clippy --all-targets --all-features -- -D warnings`
- `cargo test --no-default-features`
- `cargo build`
all inside this repo’s `zenoh-jni` directory.

Once `zenoh-jni/` is deleted from zenoh-kotlin, there are two fundamentally different choices:
1. **zenoh-kotlin no longer owns Rust lint/test quality gates** and should stop running them here; only build what zenoh-kotlin needs to execute its JVM/Android tests.
2. **zenoh-kotlin CI intentionally validates zenoh-java’s Rust code too**, which means checking out zenoh-java and running those steps there.

Those are materially different architectures. The current plan does not decide between them, and a worker could easily choose the wrong one.

### Recommended direction
The safer fit is usually:
- zenoh-kotlin CI checks out zenoh-java only as a **build dependency**,
- zenoh-kotlin CI keeps running zenoh-kotlin tests/publication checks,
- zenoh-java keeps owning its own Rust fmt/clippy/test pipeline.

If that is the intended architecture, the plan should say so explicitly and remove/reduce Rust-quality steps from this repo instead of vaguely “applying the same changes.”

## Minor non-blocking corrections
1. **`publish-android.yml` does not currently contain the same manifest-path/packaging logic as `publish-jvm.yml`.**
   The main Android change is the extra checkout plus making Gradle’s Android cargo wiring point at the external module. The plan’s wording there is a little inaccurate, though this is not a blocker by itself.

2. **Docs will need touch-ups.**
   `README.md` currently tells users zenoh-kotlin itself compiles `zenoh-jni` locally. After the migration, the local-build instructions should mention the zenoh-java checkout requirement or whatever replacement flow is chosen.

## Bottom line
The plan has the right high-level direction and I do not see missing JNI in the provided zenoh-java branch.

But I would send it back for one revision before implementation:
- make toolchain ownership explicit for external cargo invocations, and
- make CI ownership explicit for Rust fmt/clippy/test/build after `zenoh-jni/` is removed from this repo.

Until those two points are nailed down, the plan is likely to produce a fragile or incorrect build/CI integration.
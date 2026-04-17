I reviewed the revised plan against the current zenoh-kotlin repository and the referenced zenoh-java PR 465 surface. The overall direction is correct: consume `org.eclipse.zenoh:zenoh-jni-runtime` via an included build/submodule, remove zenoh-kotlin’s duplicated JNI wrapper and local Rust crate, and migrate callers onto the shared runtime API.

However, the plan still has blocking issues and should be revised before implementation.

## What checks out

- The repo really is still locally wired to `:zenoh-jni` in `settings.gradle.kts`, `zenoh-kotlin/build.gradle.kts`, `examples/build.gradle.kts`, and CI/publish workflows.
- The zenoh-java PR really does expose `zenoh-jni-runtime` as a separate multiplatform module with public `ZenohLoad`, `Target`, `ZError`, JNI wrapper classes, and callbacks.
- The included-build substitution approach in `settings.gradle.kts` is directionally appropriate.
- The earlier omissions around `examples/build.gradle.kts` and `publish-android.yml` were fixed in the revised plan.

## Blocking issues

1. **The plan still describes the runtime API incorrectly in several places.**

   The runtime does **not** match the signatures described in the plan:

   - `JNIConfig` in `zenoh-jni-runtime` exposes `loadDefault()`, `loadFromFile(path: String)`, `loadFromJson(raw: String)`, `loadFromYaml(raw: String)` and returns a `JNIConfig` object directly.
   - `JNISession.open(...)` is `JNISession.open(config: JNIConfig): JNISession`, not a factory that takes a raw `Long` config pointer.
   - `JNIConfig.getJson()` / `insertJson5()` throw `ZError`; they do not return `Result`, but the receiver object is still `JNIConfig`, not a raw pointer wrapper.

   The plan currently tells the worker to rewrite `Config.kt` and `Session.kt` around pointer-returning factories that do not exist in the target runtime. That is enough to send implementation in the wrong direction.

2. **The plan’s `JNIZBytes` note is now wrong.**

   The revised plan says `JNIZBytes.kt` is absent from `zenoh-jni-runtime` and must stay in zenoh-kotlin. That is no longer true for the referenced PR: `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIZBytes.kt` exists.

   Keeping the local `zenoh-kotlin` copy would recreate exactly the kind of duplicate runtime surface this migration is supposed to remove, and it risks duplicate class/package conflicts. The plan should explicitly delete the local `JNIZBytes.kt` and rely on the runtime copy.

3. **The liveliness migration section is based on a nonexistent target abstraction.**

   The plan says liveliness moved out into a separate `JNILiveliness` object in the runtime and that `Liveliness.kt` should call `JNILiveliness.declareTokenViaJNI(...)` directly. That does not match PR 465.

   In the runtime, liveliness operations are on `JNISession` itself:
   - `declareLivelinessToken(...)`
   - `declareLivelinessSubscriber(...)`
   - `livelinessGet(...)`

   A worker following the current plan would search for runtime APIs that do not exist. The plan needs to state the correct target: migrate `Liveliness.kt` from the local `JNILiveliness` helper to the shared `JNISession` liveliness methods.

4. **The release/publication story is still unresolved.**

   This is the biggest architectural gap left in the revised plan.

   The plan intentionally uses a git submodule + included build because `zenoh-jni-runtime` is not released yet. But it also keeps zenoh-kotlin’s publication workflows alive and changes the library to publish with a transitive dependency on `org.eclipse.zenoh:zenoh-jni-runtime:${rootProject.version}`.

   That raises a fundamental question the plan does not answer: **where does the published runtime artifact come from?**

   An included build is enough for local development and CI compilation, but it does not by itself make `publishJvmPublicationToSonatypeRepository` or the Android publication publish the included build’s runtime artifact. If zenoh-kotlin publishes only its own module while depending on an unreleased `zenoh-jni-runtime`, the resulting published artifact will be broken for consumers.

   The plan must pick one explicit release strategy, for example:
   - publish `zenoh-jni-runtime` from the included zenoh-java build as part of zenoh-kotlin’s release pipeline before/alongside zenoh-kotlin, or
   - make zenoh-kotlin publication depend on an already released runtime version and use the submodule/composite build only for local development, or
   - temporarily disable zenoh-kotlin publication paths until the runtime is independently releasable.

   Without this, the migration is not complete at the architecture level.

## Non-blocking but worth tightening

- The plan still keeps direct `../zenoh-java/zenoh-jni/target/...` path coupling in `examples/build.gradle.kts`. Since `zenoh-jni-runtime` already owns native loading/packaging, the cleaner target state is to let examples rely on the runtime dependency rather than hardcoding the submodule’s Rust output layout unless a specific local-run constraint proves that extra wiring is needed.
- `Config.fromJson5(...)` should remain supported. The plan should say explicitly how to preserve that API on top of the runtime surface, because the runtime exposes `loadFromJson(...)` / `loadFromYaml(...)` but no separate `loadFromJson5(...)` method.

## Required revision

Before implementation, revise the plan so it:

1. uses the **actual** PR 465 API shapes (`JNIConfig` object-returning factories, `JNISession.open(config: JNIConfig)`, liveliness on `JNISession`),
2. explicitly removes local `JNIZBytes.kt`,
3. defines a real publication strategy for `zenoh-jni-runtime` instead of only a local composite-build strategy,
4. treats hardcoded `zenoh-java/zenoh-jni/target/...` coupling as optional fallback wiring, not the main architecture.

Once those are corrected, the plan should be implementation-ready.
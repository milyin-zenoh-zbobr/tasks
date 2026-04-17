I validated the revised plan against the current zenoh-kotlin repository and the actual surface exposed by `eclipse-zenoh/zenoh-java` PR 465 (`refs/pull/465/head`). The migration direction is correct: switch zenoh-kotlin to the shared `zenoh-jni-runtime`, remove the local Rust crate, and stop carrying duplicated JNI wrapper classes. But the plan still has several blocking architecture-level problems.

## What the plan gets right

- The current zenoh-kotlin repo is still wired to the local `:zenoh-jni` module in `settings.gradle.kts`, `zenoh-kotlin/build.gradle.kts`, `examples/build.gradle.kts`, and CI/publication workflows.
- PR 465 really does introduce `zenoh-jni-runtime` as a reusable Gradle module with the shared JNI wrapper classes, callbacks, `ZError`, `Target`, and `ZenohLoad`.
- Using a submodule + Gradle composite build is a reasonable way to consume the PR branch before it is independently released.

## Blocking issues

### 1. The plan still describes several target APIs incorrectly

The revised plan is still not aligned with the actual runtime API in PR 465:

- `JNIConfig` exposes `loadDefault()`, `loadFromFile(path: String)`, `loadFromJson(raw: String)`, and `loadFromYaml(raw: String)`, each returning a `JNIConfig` object.
- `JNISession.open(...)` is `JNISession.open(config: JNIConfig): JNISession`, not an API that takes a raw config pointer.
- There is no `loadJson5Config()` entrypoint in the runtime. In zenoh-java’s own facade, `fromJson5(...)` is preserved by mapping it to `JNIConfig.loadFromJson(...)`.
- Liveliness operations are on `JNISession` itself (`declareLivelinessToken`, `declareLivelinessSubscriber`, `livelinessGet`), not on a separate shared `JNILiveliness` object.

Those are not detail-level mistakes. They would push the worker to rewrite `Config.kt`, `Session.kt`, and `liveliness/Liveliness.kt` around methods that do not exist.

### 2. The JNIZBytes migration is still unresolved

The plan says zenoh-kotlin should keep its local `io.zenoh.jni.JNIZBytes.kt`. That is incorrect for the referenced PR: `zenoh-jni-runtime` already contains `io.zenoh.jni.JNIZBytes`.

That makes the current plan internally inconsistent:

- **If the local file is kept**, zenoh-kotlin and zenoh-jni-runtime both define the same FQCN (`io.zenoh.jni.JNIZBytes`), which is exactly the kind of duplication this migration is supposed to remove and is likely to create duplicate-class conflicts.
- **If the local file is deleted**, the plan still does not explain how to preserve zenoh-kotlin’s serializer helpers, which currently import `JNIZBytes.serializeViaJNI` / `deserializeViaJNI` directly from `ext/ZSerialize.kt` and `ext/ZDeserialize.kt`.

The runtime’s `JNIZBytes` surface is not a drop-in match for zenoh-kotlin’s current callers, so the plan must explicitly cover the serializer adaptation. Right now it does not.

### 3. The plan leaves a duplicated logger JNI wrapper behind

The plan explicitly says logger handling should stay unchanged because the runtime has no logger wrapper. That is also incorrect.

PR 465 includes `io.zenoh.jni.JNILogger` in `zenoh-jni-runtime`. zenoh-kotlin currently has its own `io.zenoh.Logger` with a private `external fun startLogsViaJNI(...)`. Leaving that in place means the migration would still retain a custom direct JNI bridge in zenoh-kotlin instead of fully relying on the shared runtime for JNI wrapper code.

The plan needs to decide the intended end state here: either migrate `Logger.kt` to delegate through runtime `JNILogger`, or justify why this one custom bridge remains. As written, it claims the shared wrapper does not exist when it does.

### 4. Publication is still not fully solved

The revised plan improves the local-development story, but the release story is still not actually nailed down.

`remotePublication=true` skips the included build and expects `org.eclipse.zenoh:zenoh-jni-runtime` to resolve remotely. That can only work if the exact required runtime version is guaranteed to exist in the remote repository before zenoh-kotlin publication runs. The plan states that as if it were already true, but it is still an external sequencing assumption, not an implementation decision enforced by zenoh-kotlin’s own build.

At architecture level, the plan needs one explicit publication strategy, not just a hope that the artifact exists remotely:

1. publish `zenoh-jni-runtime` as part of the zenoh-kotlin release flow before publishing zenoh-kotlin, or
2. pin zenoh-kotlin to a runtime version that is already released and available, or
3. block/disable remote publication until the runtime release dependency is satisfied.

Without that, the migration can compile locally yet still publish a broken artifact.

## Non-blocking observations

- Hardcoding `../zenoh-java/zenoh-jni/target/release` in `examples/build.gradle.kts` is a brittle fallback. Since the runtime already owns native loading, examples should ideally rely on the runtime dependency rather than the included build’s cargo target layout unless there is a demonstrated local-run need.
- Deleting the local duplicate callbacks, `ZError`, `Target`, `ZenohLoad`, and the main JNI wrapper classes is otherwise directionally correct.

## Required revision before implementation

Revise the plan so that it:

1. uses the **actual PR 465 API shapes** (`JNIConfig.loadDefault/loadFromFile/loadFromJson/loadFromYaml`, `JNISession.open(config: JNIConfig)`, liveliness methods on `JNISession`),
2. explicitly covers the **serializer/JNIZBytes migration** instead of claiming the local file should stay,
3. accounts for the shared **`JNILogger`** and removes or reroutes zenoh-kotlin’s remaining direct logger JNI bridge,
4. defines a concrete **publication strategy** for `zenoh-jni-runtime` instead of relying on an unstated remote-availability assumption.

Until those are fixed, the plan is still not implementation-ready.
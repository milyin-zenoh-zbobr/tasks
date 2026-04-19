## Overall assessment
The Kotlin-side JNI migration is largely correct and consistent with the chosen analog (`zenoh-java` on `common-jni`). The direct in-repo JNI adapter layer is gone, the wrappers now call `zenoh-jni-runtime` with the same primitive/JNI-level adaptation pattern as the analog, the `ZSerialize`/`ZDeserialize` move to `jvmAndAndroidMain` matches the runtime layout, and the previously reported `README.md` / `ci/scripts/bump-and-tag.bash` issues are fixed. I verified those fixes and checked the corresponding checklist items (`ctx_rec_38`, `ctx_rec_39`).

However, I found one remaining task-level issue in the publication wiring, plus one robustness issue in the dependency versioning.

## Findings

### 1. Publish workflows are still coupled to the local `zenoh-java` submodule and Rust build
**Severity:** high

The task description draws a clear boundary:
- add `zenoh-java` as a submodule for **local building and testing**
- published `zenoh-kotlin` should **depend on** `zenoh-jni-runtime`
- publishing `zenoh-jni-runtime` is **zenoh-java's responsibility**

The current implementation still routes the publish jobs through the local submodule:
- `settings.gradle.kts:27-34` unconditionally enables `includeBuild("zenoh-java")` whenever the submodule is present, substituting `org.eclipse.zenoh:zenoh-jni-runtime` with the local project
- `.github/workflows/publish-jvm.yml:28-40` checks out submodules recursively and installs the Rust toolchain
- `.github/workflows/publish-android.yml:28-39` does the same

Because the publish workflows explicitly fetch the submodule, the composite-build substitution is active during publication. That means the zenoh-kotlin release path is still coupled to a local checkout/build of `zenoh-jni-runtime`, instead of cleanly publishing a Kotlin artifact that depends on the already-published runtime owned by `zenoh-java`.

This is inconsistent with the migration goal: the submodule should help local dev/test, not remain part of the zenoh-kotlin release pipeline.

**Suggested fix:** gate the `includeBuild("zenoh-java")` substitution behind an explicit local-dev/test property, or disable submodule checkout for the publish workflows so publication resolves against the published Maven artifact. After that, the publish jobs should not need the Rust toolchain.

### 2. `zenoh-jni-runtime` version is implicitly tied to zenoh-kotlin's own `version.txt`
**Severity:** medium

`zenoh-kotlin/build.gradle.kts:55` declares:

```kotlin
implementation("org.eclipse.zenoh:zenoh-jni-runtime:${file("../version.txt").readText().trim()}")
```

Before the migration, sharing one version file was natural because the JNI crate lived in this repository. After the migration, `zenoh-jni-runtime` is published from a different repository and owned by a different release process. Tying its version to zenoh-kotlin's own release number creates a fragile cross-repo assumption: any future version skew will make zenoh-kotlin publish a dependency on a runtime version that may not exist yet.

This is exactly the kind of partial-update hazard the new architecture should avoid.

**Suggested fix:** introduce a separate runtime version property (for example in `gradle.properties`) and use that for the Maven dependency. The local submodule path can still override it through composite-build substitution when explicitly enabled.

## Analog consistency
Aside from the publish/dependency wiring above, the implementation is consistent with the planner's analog choice:
- the domain wrappers follow the zenoh-java runtime-calling pattern
- duplicate shared classes were removed in the expected direction
- `Config.fromJson5` correctly delegates through `JNIConfig.loadFromJson(...)`, matching the upstream API reality
- the serialization move to `jvmAndAndroidMain` matches the runtime's own structure

So this is not a Kotlin-wrapper correctness problem; it is a remaining repository/build-architecture issue in how the new dependency is consumed and released.
## Overall assessment
The migration is now largely consistent with the chosen `zenoh-java` `common-jni` analog. The earlier `Query`/`Queryable` issues are fixed correctly: `Session.resolveQueryable` now forwards the runtime-provided `acceptReplies` value and restores fail-fast selector parsing, and the README now distinguishes default Maven resolution from the opt-in local-submodule path.

I did not find any remaining unchecked checklist items in the provided task context.

However, one task-related issue remains in the local-build/testing wiring.

## Finding

### 1. `zenoh.useLocalJniRuntime=true` silently falls back to Maven when the submodule is absent
**Severity:** medium

`settings.gradle.kts` enables the local composite build only when both conditions are true:
- the property is set (`zenoh.useLocalJniRuntime=true`)
- `zenoh-java/settings.gradle.kts` exists

Current code:
- `settings.gradle.kts:29-31` reads the property and then checks `file("zenoh-java/settings.gradle.kts").exists()`
- if that file is missing, the build simply skips `includeBuild("zenoh-java")` and continues resolving `org.eclipse.zenoh:zenoh-jni-runtime` from Maven

Why this is a problem:
- The README explicitly documents `gradle jvmTest -Pzenoh.useLocalJniRuntime=true` as the way to run **local integration testing against the `zenoh-java` submodule**.
- With the current wiring, a contributor who requests local-submodule mode but forgot `git submodule update --init --recursive` (or is on a checkout without the submodule populated) does **not** get that mode. They silently test against the published Maven artifact instead.
- That is exactly the kind of silent fallback the task guidance says to avoid, and it weakens the purpose of adding the submodule for local building/testing.

This also creates a robustness problem: CI explicitly opts into local mode in `.github/workflows/ci.yml:37`, but the settings logic does not actually guarantee that the local runtime is being used when that mode is requested.

**Suggested fix:** when `zenoh.useLocalJniRuntime=true`, fail fast if the submodule is not present instead of silently falling back. For example, require `zenoh-java/settings.gradle.kts` to exist and throw with a message telling the contributor to initialize/update submodules. After that, perform the `includeBuild("zenoh-java")` substitution unconditionally within the property-gated branch.

## Analog consistency
The Kotlin API adaptation itself now matches the chosen analog well. The remaining issue is not in the wrapper migration, but in the build-mode enforcement around the new submodule-backed local testing path.

## Optional follow-up improvement (non-blocking)
`zenoh-kotlin/src/commonMain/kotlin/io/zenoh/query/Query.kt:48` gives `acceptRepliesValue` a default of `ReplyKeyExpr.MATCHING_QUERY`. Since the constructor is internal and the runtime callback now provides the canonical value, removing that default would give a stronger compile-time guarantee that future internal `Query(...)` call sites cannot accidentally omit it and regress back to an inferred/default mode.
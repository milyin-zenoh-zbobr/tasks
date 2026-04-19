## Overall assessment
The migration itself is in good shape. The Kotlin wrappers consistently follow the `zenoh-java` `common-jni` analog, the local JNI adapter layer and in-repo Rust crate are removed, publication now resolves `zenoh-jni-runtime` from Maven by default, and the separate runtime-version property fixes the earlier cross-repo version-coupling issue.

However, one task-related issue remains in the documentation for the new local-build/testing model.

## Finding

### README still describes submodule-backed local testing/building as the default path
**Severity:** medium

The final implementation makes the local `zenoh-java` composite build explicitly opt-in:
- `settings.gradle.kts:27-31` only enables `includeBuild("zenoh-java")` when `zenoh.useLocalJniRuntime=true`
- `gradle.properties:8-12` sets that property to `false` by default
- `.github/workflows/ci.yml:36-37` passes `-Pzenoh.useLocalJniRuntime=true` explicitly when CI wants to test against the local submodule

But the README still documents local testing/building as though the submodule path is automatic. In particular:
- `README.md:197-205` says `gradle jvmTest` runs tests against the JVM target and that the JNI library is provided via the `zenoh-java` submodule, which is no longer true unless the property is set
- `README.md:128-129` says no Rust toolchain is required to build zenoh-kotlin, but in the opt-in local-submodule path the submodule build may still need Rust/Cargo to build the JNI runtime locally

This matters because the task explicitly adds the submodule for local building/testing, and the final code changed that workflow from implicit to opt-in. The docs should describe that new contract precisely so contributors know when the published Maven runtime is used vs when the local submodule is used.

**Suggested fix:** update the README to distinguish the two modes clearly:
1. default build/test/publish path: resolves published `org.eclipse.zenoh:zenoh-jni-runtime` from Maven, no local submodule substitution
2. local integration path: use `-Pzenoh.useLocalJniRuntime=true` to substitute the dependency with the `zenoh-java` submodule for local development/testing
3. clarify the toolchain expectation for that local-submodule mode

## Analog consistency
The code changes themselves are consistent with the chosen analog. I did not find a remaining Kotlin-wrapper/API mismatch in the migrated implementation; the outstanding issue is that the README has not been fully updated to match the final build wiring.
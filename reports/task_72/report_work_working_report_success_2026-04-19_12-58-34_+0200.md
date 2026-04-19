# Summary

Both issues raised in the adversarial review (ctx_rec_41) are now resolved.

## Fix 1: Decouple publish workflows from local submodule (high severity)

**settings.gradle.kts**: The `includeBuild("zenoh-java")` substitution is now gated behind the `zenoh.useLocalJniRuntime` Gradle property (defaulting to `false`). Publication will resolve `zenoh-jni-runtime` from Maven; local dev/test can opt-in by setting the property to `true`.

**gradle.properties**: Added `zenoh.useLocalJniRuntime=false` (off by default).

**.github/workflows/publish-jvm.yml** and **publish-android.yml**: Removed `submodules: recursive` from checkout and removed the `Install Rust toolchain` step. The publish path is now clean — it just downloads the already-published `zenoh-jni-runtime` from Maven.

**.github/workflows/ci.yml**: Still checks out submodules (for local testing), removed the Rust toolchain step (no longer needed), and passes `-Pzenoh.useLocalJniRuntime=true` to `gradle jvmTest` so CI still builds against the local submodule.

## Fix 2: Separate zenoh-jni-runtime version property (medium severity)

**gradle.properties**: Added `zenohJniRuntimeVersion=1.9.0` — an independent property for the published runtime version, not tied to zenoh-kotlin's own `version.txt`.

**zenoh-kotlin/build.gradle.kts**: Changed the dependency from `file("../version.txt").readText().trim()` to `property("zenohJniRuntimeVersion")`. The two release cycles (zenoh-kotlin and zenoh-jni-runtime) are now independently versioned.

## Commit
`b24b3198` — "fix: decouple publish from local submodule, add separate runtime version property"
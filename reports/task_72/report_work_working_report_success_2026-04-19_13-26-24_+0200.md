## Fix applied

`settings.gradle.kts` now fails fast with a clear error message when `zenoh.useLocalJniRuntime=true` is set but `zenoh-java/settings.gradle.kts` does not exist (submodule not initialized).

Before: silently fell back to Maven resolution when the submodule was absent.

After: `require(file(...).exists()) { ... }` throws with the message:
> "zenoh.useLocalJniRuntime=true was requested but the zenoh-java submodule is not initialized. Run: git submodule update --init --recursive"

The `includeBuild("zenoh-java")` substitution now executes unconditionally within the property-gated branch (only reached after the precondition passes).

Commit: 8aa6930e
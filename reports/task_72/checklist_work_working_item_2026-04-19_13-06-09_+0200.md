Update README.md to accurately describe the two build modes:
1. Default: resolves published `org.eclipse.zenoh:zenoh-jni-runtime` from Maven — no local submodule, no Rust toolchain needed
2. Opt-in local path: pass `-Pzenoh.useLocalJniRuntime=true` to substitute with the `zenoh-java` submodule; this path may require a Rust toolchain to build the JNI runtime locally

Specifically fix:
- README.md:197-205 ("Running the tests") — currently says submodule is used automatically; update to describe the property flag
- README.md:128-129 — currently says no Rust toolchain required; add caveat for the opt-in local submodule path
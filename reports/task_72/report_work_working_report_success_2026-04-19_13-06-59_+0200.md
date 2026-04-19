# Fix: README documentation for build modes

## What was done

Updated `README.md` to accurately describe the two runtime-resolution modes introduced by the zenoh-jni-runtime migration:

### Changes in README.md

1. **Prerequisites note (line 128):** Added caveat that the "no Rust toolchain required" statement only applies to the default Maven path; the opt-in local submodule path does require a Rust toolchain.

2. **Running the tests section (lines 197-217):** Replaced the incorrect description (which said the submodule was used automatically) with a clear two-mode breakdown:
   - **Default mode:** `gradle jvmTest` — resolves `zenoh-jni-runtime` from Maven Central, no submodule or Rust needed
   - **Local submodule mode:** `gradle jvmTest -Pzenoh.useLocalJniRuntime=true` — substitutes with the `zenoh-java` composite build; requires Rust toolchain

## Commit
`c5d47161` — docs: update README to distinguish Maven vs local submodule test modes
All issues resolved. The two fixes:

1. **Publish decoupling**: `includeBuild("zenoh-java")` is now gated behind `zenoh.useLocalJniRuntime=false` (default off). Publish workflows no longer checkout submodules or install Rust. CI still uses the local submodule by passing `-Pzenoh.useLocalJniRuntime=true` to the test task.

2. **Independent runtime version**: `zenohJniRuntimeVersion=1.9.0` in `gradle.properties` replaces the shared `version.txt` read, decoupling zenoh-kotlin's and zenoh-jni-runtime's release cycles.
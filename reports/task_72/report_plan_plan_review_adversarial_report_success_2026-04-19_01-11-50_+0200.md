I reviewed plan v8 against the current zenoh-kotlin repo and the upstream `eclipse-zenoh/zenoh-java` `common-jni` branch.

Conclusion: the plan is sound and ready for implementation. I found no blocker that would invalidate the migration or indicate that `zenoh-jni-runtime` is insufficient as the JNI replacement.

What I verified:
- The current repo still has a full local JNI adapter layer under `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/**`, plus Rust build wiring in `zenoh-kotlin/build.gradle.kts`, `examples/build.gradle.kts`, `settings.gradle.kts`, CI workflows, and the root `zenoh-jni/` crate. So the plan’s removal scope matches reality.
- Upstream `zenoh-jni-runtime` on `common-jni` does provide the required JNI surface: `JNISession`, `JNIPublisher`, `JNISubscriber`, `JNIQueryable`, `JNIQuerier`, `JNIQuery`, `JNIAdvancedPublisher`, `JNIAdvancedSubscriber`, `JNIKeyExpr`, `JNIConfig`, `JNIScout`, `JNILivelinessToken`, `JNIMatchingListener`, `JNISampleMissListener`, `JNIZenohId`, callback interfaces, `JNILogger`, and `JNIZBytesKotlin` in `jvmAndAndroidMain`.
- The duplicate-class concern is real: upstream runtime also defines `io.zenoh.exceptions.ZError`, `io.zenoh.Target`, and `io.zenoh.ZenohLoad`, and `Target` is byte-for-byte identical to zenoh-kotlin’s local copy. Deleting the local copies is the correct direction.
- The serialization source-set move is consistent with upstream: `zenoh-jni-runtime` really does place `JNIZBytesKotlin` in `src/jvmAndAndroidMain/kotlin/io/zenoh/jni/`, so moving `zSerialize` / `zDeserialize` there is aligned with the runtime’s design.
- The plan correctly recognizes that this is not a drop-in dependency swap: upstream runtime methods use primitive/JNI-level signatures, so zenoh-kotlin domain classes must inline conversion and callback adaptation. The referenced zenoh-java files are appropriate analogs for that work.

Non-blocking correction:
- In the Config section, the plan says the runtime provides `JNIConfig.loadFromJson5(...)`. It does not. On the reviewed upstream branch, `JNIConfig` exposes `loadDefault()`, `loadFromFile(String)`, `loadFromJson(String)`, and `loadFromYaml(String)`. The zenoh-java analog implements `Config.fromJson5(...)` by delegating to `JNIConfig.loadFromJson(...)`, not to a dedicated `loadFromJson5(...)` method. This should be corrected before implementation so the worker does not chase a nonexistent API.

Minor observations that do not block implementation:
- Keeping a small local `JNILiveliness` helper is workable, but upstream zenoh-java now performs the liveliness callback adaptation directly in `io.zenoh.liveliness.Liveliness`. Mirroring that upstream pattern would reduce divergence.
- Verification checklist item about checking duplicate classes via `gradlew dependencies --configuration jvmRuntimeClasspath` is not very strong, because that command shows modules rather than class collisions. Compile/test success plus absence of local duplicate sources after deletion is the better signal.

Bottom line:
- `zenoh-jni-runtime` looks sufficient for zenoh-kotlin’s JNI replacement.
- The migration architecture in plan v8 is good.
- Correct the one Config API detail (`fromJson5 -> loadFromJson`) and proceed.
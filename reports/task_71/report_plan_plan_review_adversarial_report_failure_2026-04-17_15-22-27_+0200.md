I reviewed ctx_rec_9 against the current zenoh-kotlin tree and the actual APIs exposed by zenoh-java PR 465 (`refs/pull/465/head`). The overall migration direction is correct: composite build + `zenoh-jni-runtime` + deleting duplicated wrappers is the right shape, and the added Scout migration is consistent with the runtime’s `JNIScout.scout(Int, JNIScoutCallback, JNIOnCloseCallback, JNIConfig?)` API.

However, there are still two blocking problems that make the plan not implementation-ready.

1. The plan is not self-contained in zenoh-kotlin because it requires new code inside the pinned zenoh-java submodule.

The plan says to pin the submodule to PR 465 head `c4ec1d89c246a76edd03128593fd34f6641c405d`, then in Phase 3 modify `zenoh-java/zenoh-jni/src/zbytes.rs` to add `KJNIZBytes` JNI exports. That is not a normal zenoh-kotlin implementation detail; it is a required upstream change in another repository after the chosen pin.

Why this is blocking:
- PR 465 at the pinned commit does not contain the Kotlin-specific `KJNIZBytes` support. Its runtime only has Java-style `JNIZBytes` (`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIZBytes.kt`) and corresponding Rust symbols in `zenoh-jni/src/zbytes.rs` that operate on `java.lang.reflect.Type` and `ByteArray`.
- If a worker follows this plan literally inside the zenoh-kotlin repo, they can only produce a dirty submodule checkout, not a mergeable zenoh-kotlin change. A parent repo commit can only record a submodule SHA that already exists in the submodule’s remote history. The plan does not identify a companion zenoh-java commit/PR that adds `KJNIZBytes`, nor does it say the zenoh-kotlin change must wait for that upstream commit and then repin the submodule to it.
- So the worker still lacks a valid source of truth for the dependency they are supposed to consume.

What the plan needs instead:
- Either explicitly depend on a companion zenoh-java change first: “land/update zenoh-java with KJNIZBytes support, then pin the submodule to that new commit”,
- Or choose a zenoh-kotlin-only design that avoids needing new native code in the submodule.

Until that is resolved, the plan does not describe an implementable end state for this repository.

2. The plan removes zenoh-kotlin’s `Test` native-library wiring on a false premise.

Phase 2c says to remove `tasks.withType<Test> { systemProperty("java.library.path", ...) }` because `ZenohLoad` in `zenoh-jni-runtime` handles native loading from classpath resources. That is too strong, and the upstream runtime itself is evidence against it.

In PR 465, `zenoh-jni-runtime/build.gradle.kts` still keeps:
- `tasks.withType<Test> { doFirst { systemProperty("java.library.path", "../zenoh-jni/target/$buildMode") } }`

So even after introducing runtime-owned `ZenohLoad`, upstream still treats explicit test native-library path setup as necessary for test execution. The current zenoh-kotlin build has the same comment explaining this is needed for Android unit tests in host JVM runs.

Why this is blocking:
- The plan tells the worker to delete the test wiring outright without reconciling why upstream runtime still keeps it.
- That creates a real risk of regressing host/Android unit-test behavior during the migration.

What the plan needs instead:
- Either preserve equivalent `Test` wiring in zenoh-kotlin unless and until it is proven unnecessary for zenoh-kotlin’s own test matrix,
- Or explain precisely why zenoh-kotlin differs from `zenoh-jni-runtime` and can safely remove it.

Non-blocking correction worth folding into the next revision:
- The plan says `Config.fromJson5` must map to `JNIConfig.loadFromJson(raw)` because “runtime has no json5”. That is misleading. In PR 465, `zenoh-jni-runtime` indeed has no separate Kotlin API named `loadFromJson5`, but its underlying Rust `loadJsonConfigViaJNI` parses JSON5 (`json5::Deserializer::from_str(...)`). So the behavior is probably preservable, but the rationale should be corrected so the worker does not accidentally simplify away JSON5 support or its tests.

Summary:
- The migration strategy is mostly correct.
- The Scout fix is correct.
- But the plan still fails the “implementation-ready” bar because it depends on upstream code that is not actually available at the pinned submodule commit, and it removes test native-library setup without resolving the contradiction with the runtime project’s own build.
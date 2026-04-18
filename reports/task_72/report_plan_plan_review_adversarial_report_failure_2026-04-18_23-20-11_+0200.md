The overall direction is viable — make `zenoh-kotlin` consume `org.eclipse.zenoh:zenoh-jni-runtime`, add `zenoh-java` as a submodule for source-based local work, and remove the in-repo Rust crate — but the current plan has two blocking architectural problems and one important omission.

1. **The plan misidentifies what can be deleted in `zenoh-kotlin`.**
   `zenoh-jni-runtime` is **not** a drop-in replacement for zenoh-kotlin’s current `io.zenoh.jni.*` layer. It provides the low-level JNI bindings, but zenoh-kotlin’s current classes also adapt between JNI primitives and zenoh-kotlin domain types.

   Concrete examples:
   - Current `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt` constructs `Publisher`, `Subscriber`, `Queryable`, `Querier`, `Reply`, `Sample`, `KeyExpr`, etc. It is not just external declarations.
   - Current `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIConfig.kt` returns `Config` objects, not raw JNI config handles.
   - Current `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIZBytes.kt` works with `ZBytes` and `KType`.
   - In contrast, `zenoh-jni-runtime`’s `JNISession` and `JNIConfig` are lower-level bindings over primitive/handle-oriented types, and its `JNIZBytes` uses `ByteArray` + `java.lang.reflect.Type`.

   A worker following Phase 3 literally would delete the adapter layer that preserves zenoh-kotlin’s existing public API semantics. The revised plan should explicitly say:
   - remove the **external/native implementation ownership** from zenoh-kotlin,
   - keep or refactor the zenoh-kotlin adapter layer where it translates to/from `Config`, `Session`, `Publisher`, `ZBytes`, callbacks, etc.,
   - delete only the pieces that are truly duplicated by `zenoh-jni-runtime` (not the higher-level adapters themselves).

2. **The composite-build/submodule plan would break ordinary clones and current CI unless it is gated.**
   The plan proposes unconditional `includeBuild("zenoh-java")` in `settings.gradle.kts`, but the repository currently has no submodule checkout logic, and Git submodules are not present in a normal clone by default.

   Today all workflows use plain `actions/checkout@v4` without `submodules:`. If `settings.gradle.kts` always includes `zenoh-java`, configuration will fail whenever the submodule is absent.

   The revised plan needs one of these explicit strategies:
   - gate `includeBuild("zenoh-java")` behind `file("zenoh-java/settings.gradle.kts").exists()`, while otherwise resolving `org.eclipse.zenoh:zenoh-jni-runtime` from Maven, or
   - require submodule checkout everywhere this repo builds/tests, including CI and contributor docs.

   Without that, the repo becomes fragile immediately after the change.

3. **The plan misses at least one required Rust removal surface: `examples/build.gradle.kts`.**
   The examples project still:
   - defines `CompileZenohJNI`,
   - invokes `cargo build --manifest-path ../zenoh-jni/Cargo.toml`,
   - sets `-Djava.library.path=../zenoh-jni/target/release`.

   Since the task requires eliminating all Rust code from zenoh-kotlin, the revised plan needs to include `examples/build.gradle.kts` explicitly. Otherwise examples will still depend on the removed local Rust crate.

4. **The CI simplification claim is currently too optimistic.**
   The plan says the composite-build approach avoids cross-repo Rust builds in zenoh-kotlin CI. That does not match the current `zenoh-jni-runtime` branch: its own build still compiles native code from `zenoh-java/zenoh-jni` for local/source builds. So if zenoh-kotlin CI validates against the submodule source before the artifact is published, Rust/NDK requirements do not disappear — they just move into the submodule build.

   This does not make the migration impossible, but the plan needs an explicit transition strategy:
   - either CI/tests for this repo consume a published `zenoh-jni-runtime` artifact,
   - or source-based validation via the submodule keeps the necessary native-toolchain setup.

**Bottom line:**
The migration target is sound, and `zenoh-jni-runtime` appears sufficient as the shared JNI runtime. But this plan is not implementation-ready because it would send the worker in the wrong direction on the adapter layer and does not define a safe build-resolution strategy for the new submodule/composite-build setup.

**What a revised plan should say instead:**
1. Add `zenoh-java` as a submodule for source-based local development.
2. Make `zenoh-kotlin` depend on `org.eclipse.zenoh:zenoh-jni-runtime`, with composite-build substitution only when the submodule is present.
3. Delete the in-repo Rust crate and all direct Cargo/rust-android wiring from `zenoh-kotlin`, **but preserve/refactor zenoh-kotlin’s Kotlin-side adapters** so they delegate to the runtime library instead of owning external JNI declarations.
4. Update `examples/build.gradle.kts` alongside the main module and workflows.
5. Define whether CI validates against the published runtime artifact or against the submodule source, and keep the necessary toolchain/setup accordingly during the transition.
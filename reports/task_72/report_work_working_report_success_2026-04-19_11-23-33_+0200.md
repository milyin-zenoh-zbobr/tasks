## Task Complete: zenoh-kotlin depends on zenoh-jni-runtime

All planned phases were implemented across multiple working sessions:

- **Phase 0**: zenoh-java added as git submodule (common-jni branch)
- **Phase 1**: Gradle build updated to depend on zenoh-jni-runtime, Rust wiring removed
- **Phase 2**: ZSerialize/ZDeserialize moved to jvmAndAndroidMain source set
- **Phase 3a**: zenoh-kotlin's JNI adapter layer and duplicate shared classes deleted
- **Phase 3b**: Zenoh.kt, Config.kt, KeyExpr.kt, ZenohId.kt, Logger.kt adapted to runtime API
- **Phase 3c**: Session.kt, Publisher.kt, AdvancedPublisher.kt, AdvancedSubscriber.kt, Query.kt, Querier.kt, Scout adapted to runtime API with inline JNI callbacks
- **Phase 3d**: JNILiveliness.kt updated to use runtime JNISession methods
- **Phase 3e**: Subscriber.kt, Queryable.kt, LivelinessToken.kt, MatchingListener.kt, SampleMissListener.kt imports updated
- **Phase 4**: All Rust code (zenoh-jni/ dir and rust-toolchain.toml) removed
- **Phase 5**: examples/build.gradle.kts updated — CompileZenohJNI task and cargo wiring removed
- **Phase 6**: CI workflows updated — Rust build steps removed, submodule checkout added

Build: `./gradlew :zenoh-kotlin:compileKotlinJvm` → BUILD SUCCESSFUL
Tests: `./gradlew :zenoh-kotlin:jvmTest` → BUILD SUCCESSFUL (all tests pass)

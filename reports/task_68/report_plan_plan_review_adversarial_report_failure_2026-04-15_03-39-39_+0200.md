I inspected the current Kotlin/JNI layout and the revised plan is close, but it still has several blocking issues that should be fixed before implementation.

1. `ZenohLoad` cannot stay `internal` after the split.

The plan says the new runtime module should define `internal expect object ZenohLoad`, then have `zenoh-java` reference it from `Logger.kt`. That will not compile once `ZenohLoad` lives in a different Gradle module, because Kotlin `internal` visibility is module-scoped, not package-scoped. In the current code, `ZenohLoad` is internal inside the same module as `Zenoh.kt` and `Logger.kt`, so that works today, but it will not work once `zenoh-java` depends on `zenoh-jni-runtime`.

Evidence:
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Zenoh.kt` defines `internal expect object ZenohLoad`
- `zenoh-java/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` and `src/androidMain/kotlin/io.zenoh/Zenoh.kt` define `internal actual object ZenohLoad`
- the plan explicitly wants `zenoh-java/src/commonMain/kotlin/io/zenoh/Logger.kt` to call `ZenohLoad`

Actionable fix: the plan must make `ZenohLoad` public (or otherwise introduce a public runtime-loading entry point in the runtime module). As written, the worker would produce a cross-module visibility error.

2. The plan omits `Target.kt`, but the moved JVM loader depends on it.

The plan says to copy the full JVM `actual object ZenohLoad` into the runtime module, but that implementation depends on `Target`, which currently lives in a separate file. The plan’s Step 1c only mentions `ZenohLoad.kt`, not `Target.kt`, so the runtime module would not compile if the worker followed it literally.

Evidence:
- `zenoh-java/src/jvmMain/kotlin/io/zenoh/Zenoh.kt` uses `Target.WINDOWS_X86_64_MSVC`, `Target.APPLE_X86_64`, `Target.LINUX_X86_64`, etc.
- `zenoh-java/src/jvmMain/kotlin/io/zenoh/Target.kt` defines that enum

Actionable fix: explicitly move/copy `Target.kt` into `zenoh-jni-runtime` alongside the JVM `ZenohLoad` implementation.

3. The plan still does not fully guard the companion-bound JNI classes.

You correctly called out the special cases for `JNIScout` and `JNISession.openSessionViaJNI`, but the same class-shape constraint also applies to other adapters you intend to refactor, especially `JNIConfig` and `JNIKeyExpr`. Their Rust exports are companion symbols (`..._00024Companion_...`), so they must remain companion methods on the Kotlin side after the split/refactor. The current plan does not say that explicitly, and because both files are being refactored, this is an easy place for the implementer to regress back into `UnsatisfiedLinkError`.

Evidence:
- `zenoh-jni/src/config.rs` exports:
  - `Java_io_zenoh_jni_JNIConfig_00024Companion_loadDefaultConfigViaJNI`
  - `Java_io_zenoh_jni_JNIConfig_00024Companion_getJsonViaJNI`
  - `Java_io_zenoh_jni_JNIConfig_00024Companion_insertJson5ViaJNI`
  - `Java_io_zenoh_jni_JNIConfig_00024Companion_freePtrViaJNI`
- `zenoh-jni/src/key_expr.rs` exports companion symbols for `tryFromViaJNI`, `autocanonizeViaJNI`, `intersectsViaJNI`, `includesViaJNI`, `relationToViaJNI`, `joinViaJNI`, and `concatViaJNI`
- current Kotlin files `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNIConfig.kt` and `JNIKeyExpr.kt` implement those through companion methods today

Actionable fix: the plan should explicitly state that `JNIConfig` and `JNIKeyExpr` must preserve their companion-based native declarations (even if their wrapper return types change), just as it already does for `JNIScout`.

4. The advanced zenoh-java facade portion is under-specified and likely overreaches the task.

The plan says `Session.kt` should gain `declareAdvancedSubscriber()` / `declareAdvancedPublisher()` methods that wrap the new runtime adapters. But the current zenoh-java codebase has no existing `AdvancedPublisher`, `AdvancedSubscriber`, `MatchingListener`, or `SampleMissListener` public facade classes at all. I searched the Kotlin sources and found no such types. That means the plan is no longer just about extracting reusable JNI glue; it is also implicitly introducing a brand-new public zenoh-java API surface, but without specifying the façade classes, ownership/lifecycle pattern, or how they should mirror existing `Publisher`/`Subscriber` conventions.

Evidence:
- no matches for `class AdvancedPublisher`, `class AdvancedSubscriber`, `class MatchingListener`, or `class SampleMissListener` under `zenoh-java/src`
- existing zenoh-java public wrappers are things like `Publisher`, `Subscriber`, `Queryable`, `Querier`, `LivelinessToken`, each with explicit lifecycle wrappers around JNI holders

Actionable fix: either:
- keep the scope focused on the runtime extraction only, leaving advanced public API design out of `zenoh-java`, or
- explicitly extend the plan with the new zenoh-java facade classes and lifecycle conventions so the worker is not forced to invent a new API ad hoc.

Summary judgment:
The overall direction—new `zenoh-jni-runtime` module with primitive-only JNI adapters shared by `zenoh-java` and future `zenoh-kotlin`—is correct. But the current plan still has concrete blocking gaps around module visibility, omitted JVM loader dependencies, companion JNI bindings, and the unplanned expansion of zenoh-java’s public API. I would not send this to implementation until those points are fixed.
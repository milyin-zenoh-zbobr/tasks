I reviewed the revised plan in `ctx_rec_7` against the current zenoh-java/zenoh-jni codebase. The overall architecture is now much better: splitting reusable primitive-only JNI adapters into a new `zenoh-jni-runtime` module is consistent with the stated goal, and the plan correctly fixes earlier blockers around `ZenohLoad` visibility, `Target.kt`, and companion-bound JNI symbols.

However, I would still stop implementation at this point because the plan leaves several concrete cross-module ABI issues unresolved.

1. `JNIConfig.ptr` and `JNIKeyExpr.ptr` still need an explicit visibility change in the plan.

The new runtime module only works if zenoh-java can keep reading raw native pointers from runtime-owned wrappers. Today that works because everything lives in one module, but after the split those `internal` properties become inaccessible across Gradle modules.

Evidence from the codebase:
- `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNIConfig.kt:23` defines `internal class JNIConfig(internal val ptr: Long)`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNIKeyExpr.kt:22` defines `internal class JNIKeyExpr(internal val ptr: Long)`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt:52` reads `config.jniConfig.ptr`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Zenoh.kt:58-59` and `97-99` pass `config?.jniConfig?.ptr ?: 0` into scouting
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Session.kt` and `keyexpr/KeyExpr.kt` repeatedly read `keyExpr.jniKeyExpr?.ptr ?: 0`

But the plan only explicitly promotes `JNISession.sessionPtr` and `JNIPublisher.ptr`. It does not explicitly promote `JNIConfig.ptr` or `JNIKeyExpr.ptr` to public. If a worker follows the plan literally, zenoh-java will fail to compile once those types move to `zenoh-jni-runtime`.

Actionable fix: the plan should explicitly require `public val ptr: Long` (or equivalent public accessor) for every moved runtime type whose pointer is read by zenoh-java, at minimum `JNIConfig` and `JNIKeyExpr`.

2. The `JNIQuery` refactor is internally inconsistent as written.

The plan says runtime `JNIQuery` should drop façade wrappers and expose the external JNI methods directly, and then `Query.kt` should call `jniQuery.replySuccessViaJNI(...)` directly. But the current class stores its native pointer as a private property, and the JNI externals take that pointer explicitly as an argument.

Evidence from the codebase:
- `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNIQuery.kt:32` defines `internal class JNIQuery(private val ptr: Long)`
- `JNIQuery.replySuccessViaJNI`, `replyErrorViaJNI`, and `replyDeleteViaJNI` all take `queryPtr: Long` explicitly
- the plan’s Step 2b says to make those externals public and Step 4e says `Query.kt` should call them directly

That leaves a mismatch: either zenoh-java must be able to read `jniQuery.ptr`, or runtime `JNIQuery` must keep primitive wrapper methods that apply `this.ptr` internally. The plan currently specifies neither.

Actionable fix: choose one of these explicitly in the plan:
- make `JNIQuery.ptr` public and keep the direct-external design, or
- keep public primitive wrapper methods on `JNIQuery` and leave the ptr private.

Without that clarification, the worker is likely to hit a dead end or produce a half-refactor.

3. The plan under-specifies preservation of the existing `Config` public API and is likely to regress it.

The current public `Config` API includes `loadDefault()`, `fromFile(File)`, `fromFile(Path)`, `fromJson()`, `fromJson5()`, and `fromYaml()`. The runtime plan only lists `loadDefaultConfig`, `loadConfigFile`, `loadJsonConfig`, and `loadYamlConfig`, and the zenoh-java Step 4 sketch even shows `fun default(): Config`, which is not the current public API.

Evidence from the codebase:
- `zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt:47-120` defines `loadDefault`, `fromFile`, `fromJson`, `fromJson5`, and `fromYaml`
- `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/JNIConfig.kt:52-55` currently preserves `fromJson5` by exposing `loadJson5Config(rawConfig: String)` as an alias over `loadJsonConfigViaJNI`
- the plan’s Step 2b omits `loadJson5Config`, and Step 4e sketches `fun default(): Config` instead of `loadDefault()`

This is not just wording noise: a worker implementing from the plan could easily remove or rename existing public `Config` entry points even though the task is about sharing JNI code, not changing the user-facing API.

Actionable fix: the plan should explicitly say that zenoh-java must preserve the current `Config` API surface unchanged, including `fromJson5()` behavior and the existing `loadDefault()` naming. If runtime does not expose a dedicated `loadJson5Config()` helper, the plan should say how zenoh-java preserves that alias.

Secondary observation:
- The plan also does not explicitly mention updating `Session.launch()` / `Session.open()` to adapt to the proposed `JNISession.open(configPtr: Long)` runtime API. That is probably recoverable during implementation, so I would not block on it alone, but it is another sign that the facade rewiring section still needs one more cleanup pass.

Summary judgment:
- The module-split direction is sound.
- The plan is not yet implementation-ready because it still misses essential cross-module pointer visibility and an internally consistent `JNIQuery` calling model, and it leaves the existing `Config` API preservation too ambiguous.

I recommend revising the plan once more to explicitly cover:
1. all moved runtime pointer properties that zenoh-java still needs (`JNIConfig.ptr`, `JNIKeyExpr.ptr`, and any others);
2. the exact `JNIQuery` model (public ptr vs retained primitive wrappers);
3. explicit preservation of the existing `Config` public API, including `loadDefault()` and `fromJson5()`.
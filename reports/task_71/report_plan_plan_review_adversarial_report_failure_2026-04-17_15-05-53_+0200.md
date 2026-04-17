I validated the latest plan against the current zenoh-kotlin codebase and the actual contents of `eclipse-zenoh/zenoh-java` PR 465 at commit `c4ec1d89c246a76edd03128593fd34f6641c405d`. The overall direction remains correct — consume `zenoh-jni-runtime`, remove the local Rust crate, and delete duplicated JNI wrappers — but the plan is still not sound enough to hand to an implementer.

## What is now correct

The plan’s corrected API descriptions for `JNIConfig`, `JNISession`, liveliness methods on `JNISession`, `JNIKeyExpr`, `JNIQuerier`, `JNILogger`, `ZenohLoad`, `Target`, and `ZError` match the PR.

It also correctly identifies the existing local build wiring that must be removed from zenoh-kotlin:
- `settings.gradle.kts` still includes `:zenoh-jni`
- root `build.gradle.kts` still applies the Rust Android plugin
- `zenoh-kotlin/build.gradle.kts` still builds `../zenoh-jni` directly, injects native libs from that directory, and configures Android cargo integration
- `examples/build.gradle.kts` still shells out to `cargo build --manifest-path ../zenoh-jni/Cargo.toml`

Those parts of the migration are well grounded.

## Blocking issues

### 1. The plan still treats `JNIZBytes` as reusable runtime API, but it is not actually consumable from zenoh-kotlin

This is the biggest remaining problem.

Current zenoh-kotlin uses a local helper at `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIZBytes.kt`:
- `internal object JNIZBytes`
- `external fun serializeViaJNI(any: Any, kType: KType): ZBytes`
- `external fun deserializeViaJNI(zBytes: ZBytes, kType: KType): Any`

And the public serializer extensions depend on that exact shape:
- `ext/ZSerialize.kt` imports `io.zenoh.jni.JNIZBytes.serializeViaJNI`
- `ext/ZDeserialize.kt` imports `io.zenoh.jni.JNIZBytes.deserializeViaJNI`

In PR 465, `zenoh-jni-runtime` does contain `io.zenoh.jni.JNIZBytes`, but its shape is materially different:
- the object is `@PublishedApi internal`, so zenoh-kotlin cannot import it from another module
- its public methods are `serialize(any: Any, type: java.lang.reflect.Type): ByteArray` and `deserialize(bytes: ByteArray, type: java.lang.reflect.Type): Any`
- the raw `serializeViaJNI` / `deserializeViaJNI` functions are `private`

So the plan’s current instruction to delete zenoh-kotlin’s local `JNIZBytes.kt` and use the runtime one is not implementable as written. Deleting the local file is necessary to avoid duplicate FQCNs, but nothing in the plan explains how zenoh-kotlin’s public `zSerialize` / `zDeserialize` API is preserved afterward.

This is not a minor omission. It is a real cross-module API mismatch:
1. visibility mismatch (`internal` runtime object),
2. type mismatch (`KType`/`ZBytes` vs `Type`/`ByteArray`),
3. current call sites in commonMain directly import methods that do not exist with the same signature in the runtime module.

The plan must explicitly choose one of these paths before implementation can start:
- require a change in `zenoh-jni-runtime` to expose a public serialization API compatible with zenoh-kotlin, or
- keep a local zenoh-kotlin serializer façade and describe exactly how it will bridge to the runtime, or
- otherwise redefine zenoh-kotlin’s serializer implementation strategy.

Without that, the worker will get stuck or make a fundamentally wrong change.

### 2. The plan deletes local `JNIScout`, but never includes the required Scout migration

The plan says to delete all local files under `io/zenoh/jni/`, including `JNIScout.kt`. That part is fine in principle because PR 465 does provide a `JNIScout`.

But the plan never accounts for the fact that zenoh-kotlin’s current `JNIScout` is not a thin alias to the runtime API — it is a domain-level adapter used directly by `io.zenoh.Zenoh`.

Current local usage:
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Zenoh.kt` calls `JNIScout.scout(whatAmI = Set<WhatAmI>, callback = ..., receiver = ..., onClose = ..., config = ...)`
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIScout.kt` converts that into primitive JNI parameters and assembles `Hello`, `ZenohId`, and `Scout<R>`.

Runtime PR 465 `JNIScout` has a lower-level API instead:
- `fun scout(whatAmI: Int, callback: JNIScoutCallback, onClose: JNIOnCloseCallback, config: JNIConfig?): JNIScout`

So deleting the local file requires a real migration in `Zenoh.kt` (or a replacement helper) to:
- reduce `Set<WhatAmI>` to the bitmask integer,
- assemble `JNIScoutCallback`,
- wrap returned data back into `Hello` / `Scout<R>`,
- pass `config?.jniConfig` instead of the current higher-level `Config?` flow.

The current plan’s only `Zenoh.kt` change is removal of the local `expect object ZenohLoad`; it never mentions Scout adaptation at all. That means the worker could faithfully follow the plan and still leave `Zenoh.kt` uncompilable after deleting `JNIScout.kt`.

This needs its own migration step, just like the plan already added for liveliness.

### 3. The runtime dependency version/publication contract is still under-specified

The plan says to add `org.eclipse.zenoh:zenoh-jni-runtime` as an `api` dependency and use `includeBuild("zenoh-java")` locally, while `remotePublication=true` should resolve the same module from Maven Central.

That direction makes sense, but the plan still does not define the actual version contract that makes publication safe:
- zenoh-kotlin `version.txt` is `1.9.0`
- zenoh-java PR 465 `version.txt` is also `1.9.0`
- but the plan never states how zenoh-kotlin will declare the runtime dependency version in Gradle metadata

That matters because the remote-publication path depends on an exact resolvable coordinate. The plan currently names only `org.eclipse.zenoh:zenoh-jni-runtime`, without saying whether the dependency version should be:
- pinned explicitly to zenoh-kotlin’s root version,
- derived from a shared property,
- or otherwise managed.

This is not just a syntactic detail. The published zenoh-kotlin artifact needs a concrete transitive dependency version, and the remote-publication strategy depends on that exact version already existing remotely. The plan should explicitly define that rule.

## Non-blocking observations

- The plan is right to migrate `Logger.kt` to the runtime’s `JNILogger`; that earlier issue is fixed.
- The plan is also right that `JNISession.open(config: JNIConfig)` and liveliness methods on `JNISession` require direct façade rewrites in `Session.kt` and `Liveliness.kt`.
- Updating examples to depend on the included build’s `buildZenohJni` task is reasonable, but the exact `java.library.path` handling is secondary compared with the serializer and scout issues above.

## Required revision before implementation

Revise the plan so that it explicitly resolves these three issues:

1. **Serializer migration:** explain how zenoh-kotlin’s `zSerialize` / `zDeserialize` survive removal of the local `JNIZBytes`, given that PR 465’s `JNIZBytes` is `internal` and has a different API surface.
2. **Scout migration:** add a concrete migration step for `Zenoh.kt` / scouting to replace the deleted local `JNIScout` adapter with the lower-level runtime API.
3. **Dependency version/publication rule:** specify exactly what version zenoh-kotlin will request for `org.eclipse.zenoh:zenoh-jni-runtime` and how that aligns with the `remotePublication=true` publishing flow.

Until those are fixed, the plan is still not implementation-ready.
I reviewed the latest plan against this repository and the upstream `zenoh-jni-runtime` on `eclipse-zenoh/zenoh-java@common-jni`. I do **not** see evidence that `zenoh-jni-runtime` is fundamentally insufficient for zenoh-kotlin; the runtime appears to expose the required native capabilities. However, the current plan is still **not implementation-ready** because its migration strategy is based on a false compatibility assumption.

## Blocking issue: the plan treats same-named runtime JNI classes as drop-in replacements, but they are not API-compatible

The plan’s core design says:
- delete all zenoh-kotlin JNI classes,
- let domain classes hold/use the runtime `io.zenoh.jni.*` types directly,
- and mostly update imports / a few call sites.

That is not sound. Multiple upstream runtime classes have the same names as zenoh-kotlin’s JNI wrappers but **different method shapes and responsibilities**, so a worker following this plan will be pushed toward broken “import swap” changes.

### 1. `JNIConfig` is not a drop-in replacement

Current zenoh-kotlin depends on wrapper-style helpers exposed by its own `JNIConfig` and used from `Config.kt`:
- local `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIConfig.kt`
- local `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Config.kt`

Today zenoh-kotlin expects methods like:
- `loadDefaultConfig()`
- `loadConfigFile(...)`
- `loadJsonConfig(...)`
- `loadJson5Config(...)`
- `loadYamlConfig(...)`
- `getJson(...)` returning `Result<String>`
- `insertJson5(...)` returning `Result<Unit>`

Upstream runtime `JNIConfig` does **not** expose that shape. It instead provides primitive JNI-facing methods such as:
- `loadDefault()`
- `loadFromFile(path: String)`
- `loadFromJson(rawConfig: String)`
- `loadFromYaml(rawConfig: String)`
- `getJson(key: String): String`
- `insertJson5(key: String, value: String)`

So `Config.kt` is **not** “just an import change after deletion of zenoh-kotlin’s version,” as the plan says. It needs an explicit adaptation strategy, like the upstream `zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt` wrapper pattern.

### 2. `JNIKeyExpr` is not API-compatible with zenoh-kotlin’s current `KeyExpr` usage

Current zenoh-kotlin `KeyExpr.kt` expects higher-level helper behavior from `JNIKeyExpr`:
- local `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/keyexpr/KeyExpr.kt`

For example, current code expects calls such as:
- `JNIKeyExpr.tryFrom(keyExpr)` yielding a `Result<KeyExpr>`-compatible construction path
- `JNIKeyExpr.autocanonize(keyExpr)` yielding a `Result<KeyExpr>`-compatible construction path
- `JNIKeyExpr.intersects(this, other)`
- `JNIKeyExpr.includes(this, other)`
- `JNIKeyExpr.relationTo(this, other)` returning a `SetIntersectionLevel`-compatible result
- `JNIKeyExpr.joinViaJNI(this, other)` / `concatViaJNI(this, other)` in the current local shape

Upstream runtime `JNIKeyExpr` is different. Its companion methods operate on primitive JNI inputs and raw strings/ints:
- `tryFrom(keyExpr: String): String`
- `autocanonize(keyExpr: String): String`
- `intersects(a: JNIKeyExpr?, aStr: String, b: JNIKeyExpr?, bStr: String): Boolean`
- `includes(...)`
- `relationTo(...): Int`
- `join(...): String`
- `concat(...): String`

This means the plan’s instruction to delete local JNI classes and then “update imports to resolve to runtime versions” is wrong for `KeyExpr`. The worker must either:
1. keep a thin zenoh-kotlin adaptation layer around runtime `JNIKeyExpr`, or
2. explicitly refactor `KeyExpr.kt` to use the upstream zenoh-java wrapper pattern.

Without that correction, the worker is likely to produce invalid code or silently change semantics.

### 3. `JNIPublisher` and similar declaration types are also not drop-in replacements

Current zenoh-kotlin `Publisher.kt` expects a wrapper object with Kotlin-domain-friendly methods:
- local `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/Publisher.kt`

Today it calls:
- `jniPublisher?.put(payload, encoding ?: this.encoding, attachment)`
- `jniPublisher?.delete(attachment)`

Upstream runtime `JNIPublisher` instead exposes primitive JNI calls:
- `put(payload: ByteArray, encodingId: Int, encodingSchema: String?, attachment: ByteArray?)`
- `delete(attachment: ByteArray?)`

So this is again **not** a pure import substitution. `Publisher.kt` (and likely analogous classes such as subscriber/query/queryable/querier wrappers) needs explicit adaptation logic. The correct analog here is the upstream `zenoh-java/src/commonMain/kotlin/io/zenoh/pubsub/Publisher.kt`, which wraps the runtime `JNIPublisher` rather than pretending its methods match the old wrapper API.

## Why this is blocking

This is not a minor implementation detail. The plan’s main migration strategy says the runtime classes can replace zenoh-kotlin’s JNI layer directly after deleting the local JNI package. In reality, several of the most central types (`JNIConfig`, `JNIKeyExpr`, `JNIPublisher`, and likely others) require either:
- a retained thin zenoh-kotlin adapter layer that delegates to `zenoh-jni-runtime`, or
- explicit rewrites of the domain classes to follow the upstream zenoh-java wrapper patterns.

As written, the plan will send an implementer in the wrong direction and cause architectural churn mid-implementation.

## What the plan should say instead

To become implementation-ready, the plan should be revised to state clearly that:

1. **`zenoh-jni-runtime` is the native backend, not a blanket drop-in API replacement.**
   Same package/class names do not imply identical Kotlin-facing methods.

2. **The migration must use upstream zenoh-java wrappers as the analog for mismatched classes.**
   In particular, `Config.kt`, `KeyExpr.kt`, and declaration classes like `Publisher.kt` must be adapted similarly to:
   - `zenoh-java/src/commonMain/kotlin/io/zenoh/Config.kt`
   - `zenoh-java/src/commonMain/kotlin/io/zenoh/keyexpr/KeyExpr.kt`
   - `zenoh-java/src/commonMain/kotlin/io/zenoh/pubsub/Publisher.kt`

3. **The plan must explicitly choose one of two strategies for incompatible JNI class shapes:**
   - preserve thin zenoh-kotlin JNI adapter files (reimplemented as delegates to runtime), or
   - rewrite each affected domain class to call runtime primitives directly.

4. **The plan must not describe `Config.kt` / `Publisher.kt` / `KeyExpr.kt` as import-only changes.**
   Those are real adaptation points and should be called out as such so the worker does not assume otherwise.

## Bottom line

The runtime still appears sufficient overall, so this is **not** a failure of `zenoh-jni-runtime` itself. But the current plan remains **not ready for implementation** because it is architecturally misleading about how compatible the runtime JNI classes are with zenoh-kotlin’s current wrappers.
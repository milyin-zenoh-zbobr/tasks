I reviewed plan v6 against the local repository and the upstream `eclipse-zenoh/zenoh-java` `common-jni` branch. I still do **not** see evidence that `zenoh-jni-runtime` is insufficient as the JNI replacement; the runtime exposes the needed JNI surface, including session operations, advanced pub/sub, liveliness, scouting, config/keyexpr helpers, logging, and Kotlin-aware serialization (`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`, `.../JNIAdvancedSubscriber.kt`, `.../JNIScout.kt`, `.../JNIConfig.kt`, `.../JNIKeyExpr.kt`, `.../jvmAndAndroidMain/kotlin/io/zenoh/jni/JNIZBytesKotlin.kt`).

However, the plan is still **not implementation-ready** because it misses another same-FQCN duplicate-class conflict.

## Blocking issue: `io.zenoh.Target` is duplicated and the plan does not remove the local copy

The plan now correctly handles the `ZenohLoad` and `ZError` conflicts, but it still leaves behind this file in zenoh-kotlin:
- local: `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt`

That class is:
```kotlin
package io.zenoh
internal enum class Target { ... }
```

The upstream runtime also ships the same file/FQCN:
- upstream: `zenoh-jni-runtime/src/jvmMain/kotlin/io/zenoh/Target.kt`

It is also:
```kotlin
package io.zenoh
internal enum class Target { ... }
```

This matters because plan v6 explicitly says to delete zenoh-kotlin’s platform `ZenohLoad` files and use the runtime’s `io.zenoh.ZenohLoad` instead (ctx_rec_12, lines 21-24 and 102-104), but it does **not** say to delete the local `Target.kt`. Once zenoh-kotlin depends on `zenoh-jni-runtime`, both modules would contribute `io/zenoh/Target.class` on the JVM classpath/publication.

Even though `Target` is `internal` at the Kotlin source level, it is still a real class with the same FQCN in both artifacts. Leaving it in place creates the same kind of packaging/classpath problem the plan already recognized for `ZError` and `ZenohLoad`.

## Why this blocks implementation

A worker following the current plan can do everything “correctly” according to the plan and still end up publishing or testing with duplicate `io.zenoh.Target` classes. This is not a cosmetic omission; it is another module-boundary conflict caused directly by the migration design.

## What the plan should say

Add an explicit duplicate-class rule for `Target` alongside `ZError`/`ZenohLoad`, for example:
- delete `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt`, since zenoh-kotlin will no longer own the JNI library loader implementation, and
- rely on the runtime’s `io.zenoh.Target` transitively through runtime `ZenohLoad`, ensuring only one definition is packaged.

At minimum, Phase 3a’s deletion list must include `zenoh-kotlin/src/jvmMain/kotlin/io/zenoh/Target.kt`.

## Bottom line

`zenoh-jni-runtime` still appears sufficient overall, so this is **not** a failure of the runtime itself. But plan v6 remains **not ready for implementation** because it still misses a real duplicate-class conflict (`io.zenoh.Target`). Once that is incorporated, the plan should be much closer to implementation-ready.
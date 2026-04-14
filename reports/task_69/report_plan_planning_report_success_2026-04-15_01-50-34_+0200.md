# Architecture: Make zenoh-kotlin JNI-free, Depend on zenoh-java

## Problem

zenoh-kotlin currently contains its own `zenoh-jni` Rust module (~3,900 LOC) and `io.zenoh.jni.*` Kotlin adapter classes managing raw Rust pointers. The goal is to make zenoh-kotlin a pure Kotlin library that delegates all JNI/native concerns to zenoh-java, keeping its Kotlin-idiomatic public API intact (`Result<T>`, `Channel<T>`, `AdvancedPublisher`/`AdvancedSubscriber`).

## Two-Layer Architecture

```
User Code (imports io.zenoh.*)
        ↓
zenoh-kotlin  [pure Kotlin, no JNI]
  - Session wrapper: adds Channel<T> / Result<T> APIs on top of zenoh-java
  - ChannelHandler (Kotlin coroutines Channel)
  - AdvancedPublisher / AdvancedSubscriber wrappers
  - Data types (Sample, ZBytes, etc.) re-exported from zenoh-java
        ↓
zenoh-java  [Kotlin + JNI bridge]
  - Core API: Session, Publisher, Subscriber, Queryable, Querier, ...
  - NEW: AdvancedPublisher, AdvancedSubscriber, MatchingListener, SampleMissListener
  - zenoh-jni Rust module (owns ALL native code)
        ↓
zenoh-jni (Rust) → zenoh core (Rust)
```

## Key API Differences to Bridge

| Concern | zenoh-java (current) | zenoh-kotlin (must keep) |
|---|---|---|
| Error handling | throws `ZError` | returns `Result<T>` |
| Streaming | `BlockingQueue<Optional<T>>` | `Channel<T>` (coroutines) |
| Advanced pub/sub | absent | `AdvancedPublisher`, `AdvancedSubscriber` |

Channel wrapping is straightforward: zenoh-kotlin creates `Callback<T>` lambdas that `channel.send(t)`, then calls zenoh-java's callback-based API. `Result<T>` wrapping uses `runCatching { }` around zenoh-java calls.

## Changes Required in zenoh-java

This is the critical prerequisite: zenoh-java must absorb the zenoh-ext features currently only in zenoh-kotlin.

### 1. Enable zenoh-ext in zenoh-jni
- In `zenoh-jni/Cargo.toml`: enable the `zenoh-ext` Cargo feature
- This unlocks `AdvancedPublisher`, `AdvancedSubscriber`, etc. from Rust

### 2. Port Rust JNI functions for advanced features
Port from zenoh-kotlin's `zenoh-jni/src/ext/` into zenoh-java's `zenoh-jni/src/ext/`:
- `advanced_publisher.rs` — JNI functions for AdvancedPublisher operations
- `advanced_subscriber.rs` — JNI functions for AdvancedSubscriber operations
- `matching_listener.rs` — JNI functions for MatchingListener
- `sample_miss_listener.rs` — JNI functions for SampleMissListener

### 3. Add Kotlin JNI adapter classes (internal) in zenoh-java
In `zenoh-java/src/commonMain/kotlin/io/zenoh/jni/`:
- `JNIAdvancedPublisher.kt`, `JNIAdvancedSubscriber.kt`
- `JNIMatchingListener.kt`, `JNISampleMissListener.kt`

### 4. Add public Kotlin API classes in zenoh-java
In `zenoh-java/src/commonMain/kotlin/io/zenoh/pubsub/`:
- `AdvancedPublisher.kt` — mirrors zenoh-kotlin's API
- `AdvancedSubscriber.kt` — mirrors zenoh-kotlin's API

In `zenoh-java/src/commonMain/kotlin/io/zenoh/ext/`:
- `CacheConfig.kt`, `HistoryConfig.kt`, `MissDetectionConfig.kt`, `RecoveryConfig.kt` (data classes for advanced pub/sub configuration)

### 5. Add Session methods in zenoh-java
Add `declareAdvancedPublisher(...)` and `declareAdvancedSubscriber(...)` overloads to zenoh-java's `Session.kt`.

## Changes Required in zenoh-kotlin

### 1. Remove the native/JNI layer entirely
- Delete `zenoh-jni/` directory (entire Rust module, ~3,900 LOC)
- Delete all `io.zenoh.jni.*` Kotlin adapter classes
- Remove `zenoh-jni` from `settings.gradle.kts`
- Remove Rust compilation tasks from `zenoh-kotlin/build.gradle.kts`

### 2. Add zenoh-java as a Gradle dependency
```kotlin
commonMainImplementation("org.eclipse.zenoh:zenoh-java:<version>")
```

### 3. Rewrite Session.kt
- Hold an internal reference to zenoh-java's `io.zenoh.Session`
- Wrap every call in `runCatching { }` to return `Result<T>`
- Implement Channel-based overloads: create `Callback<T>` lambdas that call `channel.send(t)`, delegate to zenoh-java's callback API
- Delegate `declareAdvancedPublisher`/`declareAdvancedSubscriber` to zenoh-java's new methods

### 4. Rewrite Publisher.kt, Subscriber.kt, Queryable.kt, Querier.kt
- Wrap the corresponding zenoh-java types
- Add `Result<T>` wrapping around exception-throwing calls

### 5. Reuse data types directly from zenoh-java (no wrapping needed)
The following types are identical in both projects — just use zenoh-java's versions:
- `io.zenoh.sample.Sample`
- `io.zenoh.bytes.ZBytes`, `Encoding`
- `io.zenoh.keyexpr.KeyExpr`, `SetIntersectionLevel`
- `io.zenoh.qos.*` (QoS, Priority, Reliability, CongestionControl)
- `io.zenoh.config.ZenohId`
- `io.zenoh.query.Reply`, `Query`, `Selector`, etc.
- `io.zenoh.scouting.Hello`
Since the package namespace is `io.zenoh.*` for both, users see no difference.

### 6. Keep Kotlin-specific additions
- `ChannelHandler.kt` — stays (uses Kotlin `Channel<T>`)
- `AdvancedPublisher.kt`, `AdvancedSubscriber.kt` — now wrap zenoh-java's new types
- Kotlin extension functions remain in zenoh-kotlin

## Rationale for This Approach

1. **Wrapper pattern over typealias**: Because zenoh-java throws exceptions while zenoh-kotlin returns `Result<T>`, and uses `BlockingQueue` while zenoh-kotlin uses `Channel<T>`, a thin wrapper layer is necessary. Pure typealiases would expose the wrong API.

2. **Data types reused directly**: Value/data types (Sample, ZBytes, etc.) have no behavioral difference — using them directly from zenoh-java avoids needless wrappers and keeps the API identical for users.

3. **AdvancedPublisher in zenoh-java**: Advanced features require JNI, so they must live in zenoh-java. Porting the existing Rust code from zenoh-kotlin's zenoh-jni to zenoh-java's zenoh-jni is a direct translation, not new code.

4. **Package transparency**: Both projects use `io.zenoh.*`. Since zenoh-kotlin depends on zenoh-java transiently, users importing `io.zenoh.sample.Sample` get it from zenoh-java — completely transparent.

## Verification

1. Build `zenoh-kotlin` without Rust toolchain installed — must succeed (JNI now in zenoh-java only)
2. Run all unit tests in zenoh-kotlin
3. Run end-to-end examples: ZPub, ZSub, ZGet, ZQueryable, ZAdvancedPub, ZAdvancedSub
4. Confirm no `System.loadLibrary` or `external fun` declarations in zenoh-kotlin source
5. Verify AdvancedPublisher / AdvancedSubscriber work end-to-end

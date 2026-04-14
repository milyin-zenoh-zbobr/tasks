Here's a summary of the architecture plan:

## Architecture: zenoh-kotlin as Pure Kotlin Layer over zenoh-java

### The Problem
zenoh-kotlin currently has its own ~3,900 LOC Rust JNI module and `io.zenoh.jni.*` Kotlin adapter classes managing raw Rust pointers — making it tightly coupled to native code.

### Two-Layer Design

```
zenoh-kotlin  [pure Kotlin, no JNI]
  → wraps zenoh-java types, adds Channel<T>/Result<T> APIs
        ↓
zenoh-java  [Kotlin + JNI]
  → owns ALL native code (current + new AdvancedPublisher/Subscriber)
```

### What Must Change in zenoh-java (the critical prerequisite)

zenoh-java needs to absorb the zenoh-ext features currently only in zenoh-kotlin:

1. **Enable `zenoh-ext` Cargo feature** in its `zenoh-jni/Cargo.toml`
2. **Port Rust JNI code** for `AdvancedPublisher`, `AdvancedSubscriber`, `MatchingListener`, `SampleMissListener` from zenoh-kotlin's ext/ module
3. **Add Kotlin JNI adapter classes** (internal): `JNIAdvancedPublisher`, `JNIAdvancedSubscriber`, etc.
4. **Add public API classes**: `AdvancedPublisher`, `AdvancedSubscriber`, config data classes
5. **Add Session methods**: `declareAdvancedPublisher(...)`, `declareAdvancedSubscriber(...)`

### What Changes in zenoh-kotlin

1. **Delete** the entire `zenoh-jni/` Rust module and all `io.zenoh.jni.*` Kotlin classes
2. **Add zenoh-java as a Gradle dependency**
3. **Thin wrappers**: `Session`, `Publisher`, `Subscriber`, etc. wrap zenoh-java types, adding `Result<T>` (via `runCatching`) and `Channel<T>` support (via `Callback<T>` lambdas that `channel.send(t)`)
4. **Data types** (`Sample`, `ZBytes`, `KeyExpr`, etc.) used directly from zenoh-java — same `io.zenoh.*` package, transparent to users
5. **Keep** `ChannelHandler`, `AdvancedPublisher`/`AdvancedSubscriber` wrappers in zenoh-kotlin
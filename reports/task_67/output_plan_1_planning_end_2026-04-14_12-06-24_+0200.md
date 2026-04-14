The plan has been submitted. Here's a summary of the architectural approach designed:

## Plan Summary: Make zenoh-kotlin Based on zenoh-java

**Core Insight:** Both projects use `io.zenoh.*` package names with identical class names. By *removing* zenoh-kotlin's duplicate classes, zenoh-java's fill the namespace automatically — **no shading required**.

### What gets removed from zenoh-kotlin (~50 Kotlin files, ~15 Rust files):
- All base classes: `Session`, `Config`, `Zenoh`, `Publisher`, `Subscriber`, `Querier`, `Queryable`, `Query`, `KeyExpr`, `ZBytes`, `Sample`, QoS types, handlers, etc.
- All corresponding JNI adapters: `JNISession`, `JNIConfig`, `JNIPublisher`, etc.
- All base Rust modules in `zenoh-jni/src/*.rs`

### What stays in zenoh-kotlin (unique features):
- `io.zenoh.ext.*`: `AdvancedPublisher`, `AdvancedSubscriber`, `MatchingListener`, `SampleMissListener` — NOT in zenoh-java
- Their JNI adapters and Rust ext modules (`zenoh-jni/src/ext/`)
- A new `SessionExt.kt` with extension functions for `session.declareAdvancedPublisher(...)` etc.

### Critical challenge:
The advanced features need the raw Rust session pointer, currently stored in zenoh-java's `internal JNISession.sessionPtr`. This requires either (preferred) coordinating with zenoh-java to expose an accessor, or (fallback) using JVM reflection.

### User-facing impact:
Zero — same class names, same method signatures, same package namespace.
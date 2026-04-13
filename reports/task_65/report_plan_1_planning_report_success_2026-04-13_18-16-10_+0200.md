# Implementation Plan: Connectivity API for zenoh-kotlin

## Summary
Full 3-layer binding for zenoh's connectivity API: public Kotlin types → JNI bridge → Rust JNI functions.

## Key Design Decisions
- **Analogs**: `MatchingListener`/`JNIMatchingListener` for undeclarable listener pattern; `JNILiveliness`/`Liveliness` for session-delegating object; `ext/advanced_publisher.rs` for Rust-to-JVM callback closure
- **No new Rust features needed**: `unstable` + `internal` already enabled in `zenoh-jni/Cargo.toml`
- **connectivity.rs placed at top-level** `zenoh-jni/src/` (not in ext/) — uses zenoh core, not zenoh-ext
- **Transport filter for links**: passed as primitive fields + boolean flag (avoiding reconstructing Rust Transport from Kotlin)
- **priorities field**: exposed as `Pair<Int,Int>?` (raw u8 values, can include 0=Control not in Priority enum)

## New Files (14)
### Kotlin data types (`io.zenoh.session.connectivity`)
- `Transport.kt`, `Link.kt`, `TransportEvent.kt`, `LinkEvent.kt`
- `TransportEventsListener.kt`, `LinkEventsListener.kt` — mirror `MatchingListener` pattern

### JNI handle classes (`io.zenoh.jni`)
- `JNITransportEventsListener.kt`, `JNILinkEventsListener.kt` — mirror `JNIMatchingListener`

### JNI callbacks (`io.zenoh.jni.callbacks`)
- `JNITransportCallback.kt`, `JNILinkCallback.kt` (sync snapshot)
- `JNITransportEventCallback.kt`, `JNILinkEventCallback.kt` (async events)

### JNI bridge
- `JNIConnectivity.kt` — internal object with 4 public methods + 4 external fun declarations

### Rust
- `zenoh-jni/src/connectivity.rs` — 6 JNI functions (getTransports, getLinks, declareTransportEventsListener, declareLinkEventsListener, 2x freePtrViaJNI)

## Modified Files (2)
- `SessionInfo.kt` — 4 new `@Unstable` methods
- `lib.rs` — add `mod connectivity;`

## Type Mappings
- ZenohId → jbytearray (16 bytes LE)
- WhatAmI → jint (Router=1, Peer=2, Client=4)
- SampleKind → jint (Put=0, Delete=1)
- Reliability → jint (BestEffort=0, Reliable=1) + boolean flag for Option
- Locator → jstring via to_string()
- Vec&lt;String&gt; → jobjectarray
- Option&lt;(u8,u8)&gt; priorities → boolean flag + 2x jint

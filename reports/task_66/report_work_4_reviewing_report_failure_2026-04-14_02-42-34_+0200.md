# Review: connectivity API for zenoh-kotlin

## Overall assessment
The implementation is largely solid and the chosen analog is appropriate.

The Kotlin surface follows the existing `SampleMissListener` / handler / channel-handler pattern well:
- pure snapshot data classes for `Transport` and `Link`
- dedicated callback/handler/channel types
- foreground listeners registered through `Session.strongDeclarations`
- JNI listener wrappers matching the existing listener resource pattern
- Rust callback wiring using `GlobalRef + JavaVM + attach_current_thread_as_daemon`, consistent with the existing listener implementations

So the main architecture and analog choice look correct.

## Must-fix finding

### 1. `ConnectivityTest` does not satisfy the task requirement to use unique ports per test
**Why this matters:** The task plan explicitly required using unique ports ("7465+ to avoid conflicts with other tests"). The committed test file instead defines a single shared port and reuses it across all nine tests.

**Evidence**
- `zenoh-kotlin/src/commonTest/kotlin/io/zenoh/ConnectivityTest.kt:30-40`
  - `private const val LISTEN_PORT = 7460`
  - both `listenerConfig()` and `connectConfig()` are built from that one constant
- Every test in the file opens real sessions using that same endpoint.

**Impact**
This makes the suite more order-dependent and more prone to flakes:
- if a previous test has not fully released the socket yet, the next test can fail spuriously
- if test execution is parallelized later, these tests will conflict immediately
- several of these tests exercise async listener teardown/background callbacks, which increases the chance that socket release lags the test body

**Why this is a task-requirement miss**
This is not just a style preference; it directly contradicts the planned requirement for the test file.

**Suggested fix**
Use a unique port per test instead of a single class-wide constant. For example:
- assign a distinct constant per test (starting at 7465 as planned), or
- add a helper that takes a port argument and have each test pass its own port.

## Non-blocking observation

### Snapshot JNI marshalling is fairly brittle
The snapshot path between Rust and Kotlin uses positional `Object[]` payloads with magic indexes, and the link layout even reserves an unused slot:
- `zenoh-jni/src/connectivity.rs:128-130`
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt:586-601`

This works, but it is easy to break with partial updates because Rust and Kotlin must keep the exact index contract in sync manually. I would not block the PR on this alone, but if this area evolves again, a typed callback/list shape like the existing `JNIScout` flow would be safer.

## Conclusion
The implementation is otherwise consistent with the planned analog and appears complete, but the new test suite misses the explicit unique-port requirement and should be fixed before acceptance.
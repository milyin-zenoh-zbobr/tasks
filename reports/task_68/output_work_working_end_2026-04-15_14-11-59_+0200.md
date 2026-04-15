All work is complete. Here's what was accomplished:

**`zenoh-jni-runtime` module created** — a new Gradle subproject with:
- `ZenohLoad`/`Target`/`ZError` moved from `zenoh-java`
- All JNI adapter classes (`JNISession`, `JNIConfig`, `JNIKeyExpr`, `JNIPublisher`, `JNIQuery`, `JNIQuerier`, `JNIScout`, `JNILiveliness`, etc.) refactored to primitive-only public APIs
- 7 callback interfaces (5 migrated + 2 new: `JNIMatchingListenerCallback`, `JNISampleMissListenerCallback`)
- 4 new adapters: `JNIAdvancedPublisher`, `JNIAdvancedSubscriber`, `JNIMatchingListener`, `JNISampleMissListener`

**`zenoh-java` facade updated** — `Session`, `Config`, `KeyExpr`, `Publisher`, `Query`, `Querier`, `Zenoh`, and `Liveliness` all now inline their callback assembly and call into the runtime's primitive APIs.

**Verification**: 97 tests pass, no facade imports in `zenoh-jni-runtime`.
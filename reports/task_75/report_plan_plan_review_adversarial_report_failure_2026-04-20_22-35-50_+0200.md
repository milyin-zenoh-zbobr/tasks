I inspected the revised plan from ctx_rec_5 against the current codebase. The Rust-side inventory is substantially correct: `throw_exception!` is present in the 15 files the plan names, with 55 call sites total (54 exported JNI paths plus the async `load_on_close` case in `utils.rs`). The plan also correctly identifies the key runtime adapter files and the general split of responsibility: Rust/runtime stop throwing, zenoh-java recreates `ZError` and throws it from Kotlin.

However, the plan still has a blocking omission on the zenoh-java side, so I do not consider it ready for implementation yet.

## Blocking issue

### Missing zenoh-java liveliness wiring
The plan’s Phase 5 call-site list does not include `zenoh-java/src/commonMain/kotlin/io/zenoh/liveliness/Liveliness.kt`, but that file directly calls the `JNISession` methods that Phase 3/4 explicitly changes:
- `declareLivelinessToken(...)`
- `livelinessGet(...)`
- `declareLivelinessSubscriber(...)`

These are not routed through `Session.kt`; `Liveliness.kt` calls them directly today. Evidence:
- `zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt:328-363` defines those runtime methods.
- `zenoh-java/src/commonMain/kotlin/io/zenoh/liveliness/Liveliness.kt:61-63, 80-86, 103-109, 126-132, 171-173, 190-192, 210-212` invokes them from the public API layer.

Once the runtime signatures change to take `error: Array<String?>` and return sentinel values instead of throwing, `Liveliness.kt` must allocate the error array, inspect the sentinel, and rethrow `ZError` from zenoh-java just like the other call sites. If this file is not part of the implementation plan, the worker is very likely to leave the liveliness API broken or inconsistent.

## Minor clarity issue
Phase 4’s runtime return-type guidance is narrower than the actual JNI surface. The plan correctly states the general rule for `jobject`/`jbyteArray` returning null on error, but the Kotlin bullet only explicitly lists `String -> String?` and `ByteArray -> ByteArray?`. In practice, the worker will also need to treat object-returning adapters as nullable, e.g. the `List<ByteArray>` returns behind `getPeersZidViaJNI` / `getRoutersZidViaJNI`, and the `Any` return behind `JNIZBytes.deserialize`. This is probably recoverable during implementation, but it should be stated plainly to avoid another partial pass.

## Recommendation
Revise the plan to explicitly add `zenoh-java/src/commonMain/kotlin/io/zenoh/liveliness/Liveliness.kt` to Phase 5, with the same zenoh-java-side `error` array / sentinel-to-`ZError` translation pattern used elsewhere. I would also tighten Phase 4 wording so it explicitly says that all object-returning runtime wrappers become nullable, not just strings and byte arrays.

Until that is fixed, I do not think the plan is fully implementation-ready.
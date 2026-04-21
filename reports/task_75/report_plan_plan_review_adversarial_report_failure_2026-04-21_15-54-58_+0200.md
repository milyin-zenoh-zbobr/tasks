The latest plan fixes the earlier layering problem around raw native handles, and the direction of keeping `ZError` creation only in `zenoh-java` is correct. But I do **not** think it is ready for implementation yet, because there is still a contract-level gap that will very likely leave the branch in a mixed ABI state.

## 1. The new `String?` + `out` contract is still underspecified for scalar results

The corrected requirement says the JNI return value is **always** `String?` (`null` = success, non-null = error), and the **real** return value goes through an `out` parameter. The plan now defines `out` handling for:
- raw/native handles
- `ByteArray`
- `String`
- `Any`
- `List<ByteArray>`
- void-like operations

But it still does **not** define the `out` shape for scalar-returning APIs such as booleans / enum ordinals / integer status values.

Those APIs are real and currently active in this branch:
- `JNIKeyExpr.intersects/includes/relationTo` still return `Int` in the runtime (`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIKeyExpr.kt:35-61`) and are consumed as scalar results in `zenoh-java/src/commonMain/kotlin/io/zenoh/keyexpr/KeyExpr.kt:109-160`.
- `JNIAdvancedPublisher.getMatchingStatus` still returns `Int` in the runtime (`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedPublisher.kt:40-61`).

If the plan does not explicitly say how these move to the new ABI (for example `IntArray(1)` / equivalent typed out parameter), the worker can easily either leave them on the old pattern or invent incompatible signatures ad hoc. Given the previous review iterations already missed real surfaces, this is a blocking omission, not a cosmetic one.

## 2. Several existing JNI surfaces are still omitted from the plan’s API coverage

The runtime/Java mapping tables and caller file list still do not cover several live APIs that currently use the old `error: Array<String?>` pattern and must migrate with the rest of the branch:

- `JNIKeyExpr` (`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIKeyExpr.kt:27-61`) and `zenoh-java/src/commonMain/kotlin/io/zenoh/keyexpr/KeyExpr.kt:81-160`
- `JNIZenohId` (`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIZenohId.kt:20-29`) and `zenoh-java/src/commonMain/kotlin/io/zenoh/config/ZenohId.kt:26-30`
- `JNILogger` (`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNILogger.kt:20-33`) and `zenoh-java/src/commonMain/kotlin/io/zenoh/Logger.kt:27-37`
- `JNIQuerier.get` (`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIQuerier.kt:23-48`)
- `JNIQuery.replySuccess/replyError/replyDelete` (`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIQuery.kt:24-87`)
- `JNIAdvancedSubscriber` background/object-returning methods (`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedSubscriber.kt:28-78`)
- `JNIAdvancedPublisher` methods besides the object-returning one already discussed (`zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedPublisher.kt:27-61`)

Some of these are void-like and some return real values, but they all sit on the same ABI boundary the task is changing. The plan says “update Rust JNI export functions” in general, but after earlier misses, the worker needs a complete enough architecture map to avoid another partial migration.

## 3. The proposed `make_error_jstring` helper has a success/error ambiguity

The plan proposes a helper like:

```rust
pub(crate) fn make_error_jstring(env: &mut JNIEnv, msg: &str) -> jstring {
    match env.new_string(msg) {
        Ok(s) => s.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}
```

That is dangerous under the new contract because `null` is also the **success** sentinel. If creating the Java string fails, the callee would report apparent success while leaving the `out` value unset. The current code’s `set_error_string` already degrades badly when string creation fails (`zenoh-jni/src/errors.rs:40-51`), but under the new ABI this becomes more serious because the return channel itself is the only error signal.

I would not block the overall approach on finding a perfect OOM-proof fallback, but the plan should at least acknowledge this explicitly and specify that the implementation must not silently collapse a real error into the success sentinel.

## What to fix in the plan

1. Add an explicit scalar-return rule to the ABI section, e.g. how `Boolean` / enum ordinals / status ints are written through `out` (typed array or another consistent container), and name the affected APIs.
2. Expand the coverage list so the worker knows the migration includes **all** still-live runtime/Java JNI surfaces above, not just the pointer/object/zbytes paths already listed.
3. Clarify the error-string helper behavior so a failure to materialize the error message is not treated as ordinary success.

Once those points are added, the rest of the direction looks sound: no exception throwing in `zenoh-jni-runtime`, wrapper construction stays in the runtime layer, and `zenoh-java` remains the only place that throws `ZError`.
The plan addresses all issues raised in the adversarial review:

1. **Correct Kotlin type hierarchy**: Uses dedicated `TransportEventsCallback`/`TransportEventsHandler<R>`/`TransportEventsChannelHandler` and link equivalents (same pattern as `SampleMissCallback`/`SampleMissHandler` — not the generic `Callback<T: ZenohType>`)

2. **Complete overload surface**: 6 overloads per listener type (callback/handler/channel × foreground/background), matching the existing `SampleMissListener` API surface

3. **Missing upstream options included**:
   - `history: Boolean = false` for both transport and link event listeners
   - `transport: Transport? = null` filter for `links()` snapshot
   - `transport: Transport? = null` filter for link event listeners

4. **Correct background listener pattern**: Uses `.background().wait()` in Rust (not manual Arc state storage)

5. **Structured JNI for `interfaces`**: Passed as Java `String[]` (`jobjectArray`), not delimiter-joined string

6. **Transport filter through JNI**: Passed as `ByteArray?` (ZenohId bytes); Rust side recovers the actual `Transport` object by searching `session.info().transports()`

7. **Stronger test coverage**: Includes history behavior and transport-filter behavior tests
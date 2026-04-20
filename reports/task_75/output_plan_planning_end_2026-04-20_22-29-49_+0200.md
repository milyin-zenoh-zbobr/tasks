The revised plan is ready. Here's what changed from the previous version:

**Gaps fixed:**
1. **zbytes.rs + zbytes_kotlin.rs** — included (2+2 calls); their Kotlin wrappers `JNIZBytes.kt` and `JNIZBytesKotlin.kt` now in scope
2. **utils.rs `load_on_close`** — async callback path: replace `throw_exception!` with `tracing::error!` (no out-parameter possible in async context)
3. **Missing Kotlin runtime wrappers** — `JNIZenohId.kt` added
4. **Missing zenoh-java call sites** — `Zenoh.kt` (scout), `ZenohId.kt` (toString), `ZDeserializer.kt`, `ZSerializer.kt`
5. **openSessionWithJsonConfigViaJNI / Yaml** — migrated even though no Kotlin wrapper exists (prevents Rust from ever resolving the ZError class)
6. **Rust file inventory** — all 15 files with throw_exception! now covered (prior plan missed key_expr.rs, publisher.rs, querier.rs, scouting.rs, logger.rs, zenoh_id.rs, advanced_subscriber.rs)
7. **Stronger verification** — grep checks for `@Throws` in runtime, not just for `ZError`
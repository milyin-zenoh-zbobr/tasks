The plan has been submitted. The key fixes over the previous iteration (ctx_rec_10) are:

1. **Added `JNIPublisher` explicitly** — the full chain (`publisher.rs` → `JNIPublisher.kt` → `Publisher.kt`) is now listed with its contract: `put` and `delete` are void-like (no `out` param, just `String?` return).

2. **Resolved the legacy session exports** — `openSessionWithJsonConfigViaJNI` and `openSessionWithYamlConfigViaJNI` are confirmed dead (not referenced in any Kotlin file) and are explicitly marked for **removal**, which is consistent with the verification grep.
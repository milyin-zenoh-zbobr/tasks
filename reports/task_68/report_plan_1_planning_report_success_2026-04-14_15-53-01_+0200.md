# Implementation Plan: Extend zenoh-java JNI for zenoh-kotlin Compatibility (Phase 1, Revised)

## Why This Approach

The adversarial review (ctx_rec_2) identified one blocking issue in the previous plan: `zenoh-ext` in zenoh-java's `Cargo.toml` was missing the `unstable` Cargo feature. The `AdvancedPublisher`, `AdvancedSubscriber`, `CacheConfig`, `HistoryConfig`, `MissDetectionConfig`, `RecoveryConfig`, `RepliesConfig` and related types are only exported by zenoh-ext when `unstable` is enabled. Without this fix, the advanced JNI code copied from zenoh-kotlin will not compile.

The reference implementation (closest analog) is `zenoh-kotlin/zenoh-jni/` at `/data/home/skynet/tasks/base/workspaces/zenoh-kotlin/task-67/zenoh-kotlin/zenoh-jni/`. All source files to create are copied verbatim from that location.

---

## Files to Modify

### 1. `zenoh-jni/Cargo.toml` (line 40)

Change `zenoh-ext` features from `["internal"]` to `["unstable", "internal"]`:

```
# Before:
zenoh-ext = { version = "1.8.0", git = "...", branch = "main", features = ["internal"], default-features = false, optional = true }

# After:
zenoh-ext = { version = "1.8.0", git = "...", branch = "main", features = ["unstable", "internal"], default-features = false, optional = true }
```

This is the root fix identified by the adversarial review. Matches zenoh-kotlin's Cargo.toml exactly.

### 2. `zenoh-jni/src/lib.rs`

Append three new module declarations:

```rust
pub(crate) mod owned_object;
pub(crate) mod sample_callback;
#[cfg(feature = "zenoh-ext")]
mod ext;
```

`#[cfg(feature = "zenoh-ext")]` for `ext` follows the same convention as existing `mod zbytes`.

### 3. `zenoh-jni/src/session.rs`

Add the following without touching any existing code:

**New imports at the top:**
- `use crate::owned_object::OwnedObject;`
- `use crate::sample_callback::SetJniSampleCallback;`
- Under `#[cfg(feature = "zenoh-ext")]`:
  - `use jni::sys::jdouble;`
  - `use zenoh_ext::{AdvancedPublisher, AdvancedPublisherBuilderExt, AdvancedSubscriber, AdvancedSubscriberBuilderExt, CacheConfig, HistoryConfig, MissDetectionConfig, RecoveryConfig, RepliesConfig};`
- Update zenoh imports to add `PublisherBuilder`, `SubscriberBuilder`, and `handlers::Callback`

**New JNI export: `Java_io_zenoh_jni_JNISession_openSessionViaJNI`** — instance-method variant (zenoh-kotlin calls this on a `JNISession` instance, while zenoh-java has `JNISession$Companion` static). Identical body to existing companion-object variant, delegates to the same `open_session(config_ptr)` helper.

**New private helper: `prepare_publisher_builder`** — copy verbatim from zenoh-kotlin `session.rs:527`. Takes session, key_expr, QoS params; returns `PublisherBuilder`. Used only by `declareAdvancedPublisherViaJNI`.

**New private helper: `prepare_subscriber_builder`** — copy verbatim from zenoh-kotlin `session.rs:749`. Takes session, key_expr, callback; returns `SubscriberBuilder` via `SetJniSampleCallback`. Used by `declareAdvancedSubscriberViaJNI`.

**New JNI export: `Java_io_zenoh_jni_JNISession_declareAdvancedSubscriberViaJNI`** — copy verbatim from zenoh-kotlin `session.rs:240`. Gated with `#[cfg(feature = "zenoh-ext")]`.

**New JNI export: `Java_io_zenoh_jni_JNISession_declareAdvancedPublisherViaJNI`** — copy verbatim from zenoh-kotlin `session.rs:365`. Gated with `#[cfg(feature = "zenoh-ext")]`.

---

## Files to Create

All files copied verbatim from zenoh-kotlin at `/data/home/skynet/tasks/base/workspaces/zenoh-kotlin/task-67/zenoh-kotlin/zenoh-jni/src/`:

| New File | Source | Lines | Purpose |
|---|---|---|---|
| `zenoh-jni/src/owned_object.rs` | `owned_object.rs` | 46 | `OwnedObject<T>`: safe Arc accessor preventing early drops |
| `zenoh-jni/src/sample_callback.rs` | `sample_callback.rs` | 138 | `SetJniSampleCallback` trait for JNI callback wiring |
| `zenoh-jni/src/ext/mod.rs` | `ext/mod.rs` | 18 | Module declarations for ext submodules |
| `zenoh-jni/src/ext/advanced_publisher.rs` | `ext/advanced_publisher.rs` | 339 | JNI exports for `JNIAdvancedPublisher` |
| `zenoh-jni/src/ext/advanced_subscriber.rs` | `ext/advanced_subscriber.rs` | 359 | JNI exports for `JNIAdvancedSubscriber` |
| `zenoh-jni/src/ext/matching_listener.rs` | `ext/matching_listener.rs` | 41 | `Java_io_zenoh_jni_JNIMatchingListener_freePtrViaJNI` |
| `zenoh-jni/src/ext/sample_miss_listener.rs` | `ext/sample_miss_listener.rs` | 41 | `Java_io_zenoh_jni_JNISampleMissListener_freePtrViaJNI` |

All helper dependencies used by these files (`decode_congestion_control`, `decode_priority`, `decode_reliability`, `get_java_vm`, `get_callback_global_ref`, `load_on_close`, `bytes_to_java_array`, `slice_to_java_string`) already exist in zenoh-java's `utils.rs` with identical signatures.

---

## Key Design Decisions

1. **Cargo.toml `unstable` fix is the root blocker**: Without it, zenoh-ext does not expose `AdvancedPublisher`, `AdvancedSubscriber` and related types, causing compile failure.
2. **Verbatim copy from zenoh-kotlin**: Minimizes risk of divergence. zenoh-java and zenoh-kotlin JNI layers share the same dependency utility functions.
3. **Additive-only**: No existing zenoh-java code is removed or modified (only appending new module declarations, imports, and functions).
4. **Feature gating**: `mod ext` and the advanced session exports use `#[cfg(feature = "zenoh-ext")]`, matching existing `mod zbytes` convention.

---

## Verification

After implementation:
1. `cargo build --manifest-path zenoh-jni/Cargo.toml` — must succeed with no errors
2. `nm -D target/debug/libzenoh_jni.so | grep openSessionViaJNI` — must show the instance-method symbol (not `$Companion`)
3. `nm -D target/debug/libzenoh_jni.so | grep Advanced` — must show `JNIAdvancedPublisher` and `JNIAdvancedSubscriber` symbols
4. `nm -D target/debug/libzenoh_jni.so | grep MatchingListener` — must show `freePtrViaJNI` symbol
5. `nm -D target/debug/libzenoh_jni.so | grep SampleMissListener` — must show `freePtrViaJNI` symbol

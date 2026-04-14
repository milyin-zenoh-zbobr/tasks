I reviewed the Phase 1 plan against the current `zenoh-java` repo and the referenced upstream `zenoh-kotlin`/`zenoh` sources.

## Verdict
The plan is **not ready for implementation** in its current form. The main blocker is a fundamental dependency mismatch: it says **“No Cargo.toml changes”**, but the proposed copied JNI code depends on `zenoh-ext` APIs that are only exported when the **`unstable`** feature is enabled.

## Blocking issue
### 1. `zenoh-ext` unstable is required, but the local crate does not enable it
The local crate currently depends on:
- `zenoh = ... features = ["unstable", "internal"]`
- `zenoh-ext = ... features = ["internal"]`

Citations:
- Local repo: `zenoh-jni/Cargo.toml:39-40`
  - `zenoh = ... features = ["unstable", "internal"]`
  - `zenoh-ext = ... features = ["internal"]`
- Proposed source repo: `zenoh-kotlin/zenoh-jni/Cargo.toml:39-40`
  - `zenoh-ext = ... features = ["unstable", "internal"]`
- Upstream `zenoh-ext` exports the advanced pub/sub surface only behind `#[cfg(feature = "unstable")]`:
  - `zenoh-ext/src/lib.rs:39-59` gates advanced modules on `unstable`
  - `zenoh-ext/src/lib.rs:67-75` re-exports `AdvancedPublisher`, `AdvancedSubscriber`, `CacheConfig`, `RepliesConfig`, `HistoryConfig`, `RecoveryConfig`, `SampleMissListener`, etc. only under `#[cfg(feature = "unstable")]`

This directly conflicts with the plan’s core assumption that the advanced JNI code can be copied in without Cargo changes. The proposed additions import exactly those unstable-only items:
- `zenoh-kotlin/zenoh-jni/src/session.rs:37-40`
- `zenoh-kotlin/zenoh-jni/src/ext/advanced_publisher.rs:23-27`
- `zenoh-kotlin/zenoh-jni/src/ext/advanced_subscriber.rs:20-22`

So as written, the implementation would fail to compile before it ever reaches the JNI symbol verification stage.

## What should change in the plan
Revise the plan to explicitly include:
1. **Updating `zenoh-jni/Cargo.toml`** so `zenoh-ext` enables `unstable` in addition to `internal`, matching the upstream `zenoh-kotlin` JNI crate.
2. Re-checking that the existing feature-gating strategy remains correct after that change (`mod ext`, advanced session exports, and any tests/build expectations).
3. Keeping the existing symbol-level verification, but after the Cargo feature fix is part of the implementation plan.

## Non-blocking observations
- The plan is otherwise directionally reasonable: the missing `openSessionViaJNI` alias is real, and the current repo already has the helper utilities (`get_java_vm`, `get_callback_global_ref`, `load_on_close`, `bytes_to_java_array`, `slice_to_java_string`) needed by `sample_callback.rs`.
- The repo currently has no local `JNIAdvancedPublisher`/`JNIAdvancedSubscriber` Kotlin classes, which is consistent with this being a JNI-surface-only phase; symbol-level verification is the right kind of validation here.

## Bottom line
The plan has a real architectural miss: **it omits the required `zenoh-ext` unstable feature enablement**. That must be fixed before implementation starts; otherwise the proposed copied advanced JNI code is not buildable in this repository.
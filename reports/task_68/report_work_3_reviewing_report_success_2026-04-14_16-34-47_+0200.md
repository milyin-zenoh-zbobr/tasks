# Review Report

## Overall assessment
The implementation is correct for the stated scope: it adds the missing JNI surface needed for zenoh-kotlin to reuse zenoh-java's JNI layer without introducing unrelated behavior changes. I did not find code-quality, correctness, or plan-alignment issues that require follow-up.

## Diff scope reviewed
Compared `origin/main...HEAD` and inspected all files changed by the task:
- `zenoh-jni/Cargo.toml`
- `zenoh-jni/src/lib.rs`
- `zenoh-jni/src/session.rs`
- `zenoh-jni/src/owned_object.rs`
- `zenoh-jni/src/sample_callback.rs`
- `zenoh-jni/src/ext/mod.rs`
- `zenoh-jni/src/ext/advanced_publisher.rs`
- `zenoh-jni/src/ext/advanced_subscriber.rs`
- `zenoh-jni/src/ext/matching_listener.rs`
- `zenoh-jni/src/ext/sample_miss_listener.rs`

No unrelated functional changes were introduced.

## Plan and analog consistency
The chosen analog was appropriate: zenoh-kotlin's existing JNI implementation is exactly the right reference for this compatibility task. The worker followed that analog consistently:
- `zenoh-ext` was updated to enable `unstable`, matching the requirement identified in planning.
- The new helper modules (`owned_object`, `sample_callback`, `ext/*`) match the upstream JNI structure.
- `session.rs` integrates the advanced publisher/subscriber exports additively and uses the same callback wiring and pointer-lifetime patterns as the existing zenoh-java JNI code.
- Feature gating is consistent with the existing crate approach (`#[cfg(feature = "zenoh-ext")]`).

The resulting code looks coherent with both the selected analog and the surrounding zenoh-java JNI patterns.

## Correctness review
### JNI surface
The implementation adds the expected advanced publisher/subscriber, matching-listener, and sample-miss-listener exports, plus the `JNISession_openSessionViaJNI` alias for zenoh-kotlin compatibility.

### Ownership/lifetime handling
The new code uses the same raw-pointer/`Arc::from_raw` conventions already established in this crate. Where repeated non-owning access is needed, `OwnedObject` preserves the original lifetime semantics cleanly and avoids accidental refcount drops.

### Type and API usage
The new builder helpers and advanced JNI functions use existing domain types (`PublisherBuilder`, `SubscriberBuilder`, `AdvancedPublisher`, `AdvancedSubscriber`, `HistoryConfig`, `RecoveryConfig`, `CacheConfig`, `MissDetectionConfig`, `RepliesConfig`) rather than introducing stringly or weakly typed glue. I did not find places where a more specific existing type should have been used.

### Robustness against inconsistent changes
The implementation derives behavior from existing zenoh/zenoh-ext types and builder APIs instead of duplicating protocol constants or inventing parallel configuration models. I did not find any brittle hardcoded mappings beyond the JNI callback signatures already inherent to this layer.

## Checklist status
All checklist items shown in the task context were already completed and the implementation matches them. There were no remaining unchecked items to verify or mark complete.

## Findings
No review findings.
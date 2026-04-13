The plan should be revised before implementation.

What is good:
- Mirroring the Kotlin listener surface after existing SampleMiss/Matching listener patterns is consistent with this repo.
- Adding snapshot queries plus callback/handler/channel overloads for transport/link events matches the existing Kotlin API style.
- Omitting `isShm` is correct for this repository’s current Rust feature set (`zenoh-jni/Cargo.toml` enables `unstable` + `internal`, not `shared-memory`).
- Using `.background().wait()` for background listeners matches the existing Rust JNI pattern in `advanced_publisher.rs` and `advanced_subscriber.rs`.

Blocking issues:

1. The plan solves transport filtering with hidden native pointer identity, but upstream/go both use reusable transport snapshots.

The issue explicitly asks to follow the Go binding approach: “store fields in native structure”. The current plan instead introduces `Transport` as a Kotlin object with an internal `JNINativeTransport` pointer and relies on `Arc::into_raw` / `Arc::from_raw` round-tripping the native transport identity.

That is not aligned with the requested analog, and it also diverges from how upstream Rust models the API:
- Go uses a pure snapshot `Transport` and reconstructs a native transport from fields with `toCPtr()`.
- Upstream Rust already has `Transport::new_from_fields(...)` under the `internal` feature, and this repo already enables `internal` on the `zenoh` dependency.
- `LinksBuilder` and `LinkEventsListenerBuilder` both store `Option<Transport>` by value, not some opaque transport handle.

So the plan is building a pointer-ownership scheme where the upstream/public model is snapshot-by-value. At best this is unnecessary complexity; at worst it pushes the worker toward a Kotlin/JNI-specific transport identity model that the rest of the API does not want.

2. Under the proposed callback signatures, `Transport` values coming from events cannot be reused as transport filters.

This is the most concrete architectural bug in the plan.

The plan’s `JNITransportEventsCallback` only passes:
- `kind`
- `zid`
- `whatAmI`
- `isQos`
- `isMulticast`

There is no native transport pointer in transport events, and link events do not carry a transport object at all. But the plan also says transport-filtered APIs should use `transport?.jniNativeTransport?.ptr ?: 0L`.

That means a `Transport` obtained from a `TransportEvent` cannot carry the hidden JNI transport handle required by `links(transport)` / filtered link listeners. A worker following this plan would produce an API where a transport snapshot from an event looks valid to the user, but passing it back as a filter would silently degrade to “no filter” (because the internal pointer is null) or otherwise fail.

That is incompatible with the Go/upstream model, where transport snapshots are reusable values. The representation chosen in the plan is therefore not just a different implementation detail; it breaks a natural and important usage path.

3. The pointer-based `Transport` design introduces an ownership/lifecycle problem that the plan does not resolve.

Existing Kotlin snapshot/value objects in this repo are pure data. Existing native-pointer wrappers are declaration/resource wrappers with explicit close/undeclare behavior (`JNISampleMissListener`, `JNIMatchingListener`, publishers, subscribers, etc.).

The plan mixes those two categories by putting an internal native pointer inside a public snapshot-like `Transport` class, while:
- `Transport` itself is not `AutoCloseable`
- the public API does not expose any release step for transports returned by `transports()`
- the plan does not define how `JNINativeTransport` instances are freed for ordinary query results

So either the implementation leaks native transport allocations, or it falls back to fragile finalizer-driven cleanup on an internal helper. Both outcomes are inconsistent with this codebase’s current resource model, and both are avoided if transport filters are reconstructed from snapshot fields instead of held via hidden native pointers.

4. The plan’s rationale for raw transport identity is weaker than it claims, and it conflicts with upstream filtering behavior.

The plan says prior zid-based filtering was unsound because multiple transports to the same peer can exist, so it replaces that with raw native transport identity.

But upstream Rust’s own link-event filtering currently stores `Option<Transport>` by value and, in `broadcast_link_event`, filters by transport fields (`zid` + `is_multicast`) rather than by native object identity. That does not prove every possible field subset is sufficient for every implementation detail, but it does show the upstream model is value-based, not pointer-based. Combined with Go’s `Transport.toCPtr()` reconstruction approach, the plan’s raw-pointer identity scheme is solving the problem at the wrong abstraction level.

Required revision:
- Replace the raw-pointer round-trip design with a snapshot-based design aligned with Go/upstream.
- The plan should explicitly state that Kotlin `Transport` is a pure snapshot/value object.
- JNI should reconstruct the native transport filter from snapshot fields when needed, rather than storing hidden transport ownership in Kotlin objects.
- The revised design must preserve reusability of any `Transport` snapshot, including transports obtained from `transports()` and transports coming from event payloads.

Important implementation note to add in the revision:
- Because these listeners are session-scoped declarations, the plan should also be explicit about how Session integrates them with the existing declaration lifecycle (`strongDeclarations` / `weakDeclarations`) instead of describing them like simple `getPeersId()`-style delegations. Otherwise a worker can wire the Kotlin surface correctly but miss the session-close undeclare behavior.

Conclusion:
The API surface is close, but the transport representation/filtering design is still architecturally wrong for this repository. Revise the plan around snapshot-based transports and explicit session lifecycle integration before implementation.
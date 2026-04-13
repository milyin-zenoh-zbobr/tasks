The plan is **not sound yet**. It is internally plausible for a reduced transport/link snapshot API, but it does **not** match the connectivity surface requested by issue #647 or the upstream Rust / zenoh-go analog it cites.

## Blocking issues

1. **The plan narrows the API surface too much.**
   It only covers:
   - `transports()`
   - `declareTransportEventsListener(...)`
   - `links()`
   - `declareLinkEventsListener(...)`

   But the upstream API and the go implementation include more than that:
   - **background** transport events listener
   - **background** link events listener
   - **transport filter** for `links()`
   - **transport filter** for link events listener

   Evidence:
   - Issue #647 explicitly says to implement the API similarly to zenoh-go PR 17.
   - `zenoh-go/zenoh/transport.go` includes `DeclareBackgroundTransportEventsListener(...)`.
   - `zenoh-go/zenoh/link.go` includes `DeclareBackgroundLinkEventsListener(...)`, `Links(options *InfoLinksOptions)`, and `LinkEventsListenerOptions{ Transport ... }`.
   - Upstream Rust builders also expose these capabilities:
     - `LinksBuilder::transport(...)`
     - `LinkEventsListenerBuilder::transport(...)`
     - `TransportEventsListenerBuilder::background()`
     - `LinkEventsListenerBuilder::background()`

   As written, the plan would ship only a subset of connectivity and force a follow-up redesign.

2. **The proposed data model drops real upstream fields.**
   The plan’s `Transport` and `Link` types are incomplete compared to upstream.

   Missing from `Transport`:
   - `isShm` (shared-memory enabled)

   Missing from `Link`:
   - `authIdentifier`
   - `priorities`
   - `reliability`

   Evidence:
   - `zenoh/src/api/info.rs` defines `Transport` with `is_shm` (behind shared-memory feature).
   - The same file defines `Link` with `auth_identifier`, `priorities`, and `reliability`.
   - `zenoh-go/zenoh/transport.go` and `zenoh-go/zenoh/link.go` expose those same fields in the binding.

   This is not a minor omission: it means the Kotlin API would not actually mirror the intended connectivity model.

3. **The plan does not satisfy the issue’s “store fields in native structure” requirement.**
   The issue body explicitly says: **“Use similar approach as in go binding: store fields in native structure.”**

   The plan instead chooses a callback-per-field design for snapshots and event delivery, and explicitly frames that as avoiding native object construction. That is a mismatch with the task direction.

   This matters architecturally, not cosmetically:
   - link queries/listeners need a **transport filter** upstream
   - go solves that by keeping snapshot fields in a form that can be turned back into a native transport for filtering
   - upstream Rust also has `Transport::new_from_fields(...)`, which exists for this same class of use case

   As proposed, the plan has no story for passing a Kotlin `Transport` back into JNI for filtering links, because it intentionally avoids the native-side representation that the issue calls for.

4. **`links()` is under-specified because it omits the transport filter entirely.**
   Upstream Rust `LinksBuilder` supports `.transport(transport)`. Go mirrors that with `InfoLinksOptions{ Transport ... }`.
   The plan’s `links(): Result<List<Link>>` cannot express this at all.

   That is a functional API loss, not an implementation detail.

## Secondary but important concerns

1. **If the plan is revised to include priorities, it should not model them with the existing public `Priority` enum alone.**
   Upstream documents that link priority ranges can include numeric value `0` (control), while Kotlin’s current `Priority` enum only represents `1..7`.
   So the revised plan should use raw numeric bounds or a dedicated type that can represent the full range, not `Priority` directly.

2. **The example choice is probably off.**
   The repo already has `examples/.../ZInfo.kt`, which is the natural analog for session info APIs. Creating a separate `ZConnectivity.kt` may be fine, but the plan should at least justify why connectivity is not folded into or aligned with the existing info example.

3. **The verification plan misses the newly required surfaces.**
   It does not cover:
   - background listeners
   - link filtering behavior
   - empty transports/links results
   - the additional snapshot fields above

   This is not the main problem, but it reflects the same under-scoping.

## What a sound revised plan should cover

A revised plan should:
1. Implement the **full connectivity surface**, not just the four reduced entry points.
   At minimum include:
   - transports snapshot
   - transport events listener
   - background transport events listener
   - links snapshot **with optional transport filter**
   - link events listener **with optional transport filter**
   - background link events listener

2. Model **all upstream snapshot fields** that exist in the target zenoh version used by this repo:
   - `Transport`: zid, whatAmI, isQos, isMulticast, and shared-memory support where applicable
   - `Link`: zid, src, dst, group, mtu, isStreamed, interfaces, auth identifier, priorities, reliability

3. Explicitly address the issue’s **native-structure storage / reconstruction** requirement.
   The worker needs a clear direction for how Kotlin `Transport` values are represented so they can be used later as JNI inputs for link filtering. A pure one-way callback serialization plan is not enough.

4. Keep the good parts of the current plan:
   - `SessionInfo -> Session -> JNISession -> JNI` delegation is consistent with the codebase.
   - listener classes following the existing `SessionDeclaration` / `AutoCloseable` pattern are appropriate.
   - using generic `Callback<T> / Handler<T,R> / ChannelHandler<T>` for event delivery is consistent with the Kotlin API style.

## Verdict

The plan is **not ready for implementation**. The main problem is not coding detail; it is that the plan would implement a **reduced, non-parity API** and skips the task’s explicit native-structure requirement. It should be revised before work starts.
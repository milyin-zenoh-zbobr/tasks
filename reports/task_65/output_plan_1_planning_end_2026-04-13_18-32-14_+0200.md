The plan is ready. Here's a summary of what it covers:

## Connectivity API Implementation Plan

**What's being built:** Transport/Link inspection + event listener APIs via a 3-layer JNI stack (Rust → JNI bridge → Kotlin).

**Key fixes from the previous adversarial review:**

1. **Transport filter on `declareLinkEventsListener`** — `transport: Transport? = null` parameter added end-to-end. Filter passes as primitive fields over JNI; Rust reconstructs via `Transport::new_from_fields()` (available because `zenoh-jni` already has `internal` feature).

2. **`ZenohType` bounds** — `Transport`, `Link`, `TransportEvent`, `LinkEvent` all implement `ZenohType`, making `Callback<TransportEvent>` etc. compile.

3. **Session lifecycle wiring** — both `declare*` methods add their listener to `Session.strongDeclarations`, so `Session.close()` undeclares them automatically.

4. **Consistent filter mechanism** — single design: Kotlin snapshot → primitives over JNI boundary → Rust `new_from_fields()`. Works for both `getLinks(transport)` and `declareLinkEventsListener(transport=...)`.

5. **Test coverage** — `ConnectivityTest.kt` with 9 cases: transports, links, filtered links, transport events, link events, filtered link events, history=true, undeclare, empty results.

**API scope:** Callback-only (no Handler/Channel overloads), consistent with `MatchingListener` precedent.
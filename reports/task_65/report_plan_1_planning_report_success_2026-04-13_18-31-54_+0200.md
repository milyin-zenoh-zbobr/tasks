# Revised Implementation Plan: Connectivity API for zenoh-kotlin

## Summary of Changes from Previous Plan

This revision addresses all 5 blocking issues identified in the adversarial review:

1. **Transport filter on `declareLinkEventsListener`** — added end-to-end (Kotlin public API has `transport: Transport? = null` parameter; JNI bridge passes `hasTransportFilter + transport fields` as primitives; Rust reconstructs via `Transport::new_from_fields()`)
2. **`ZenohType` constraint** — `Transport`, `Link`, `TransportEvent`, `LinkEvent` all implement `ZenohType`
3. **Session lifecycle wiring** — `declareTransportEventsListener` and `declareLinkEventsListener` add results to `Session.strongDeclarations`, ensuring `Session.close()` undeclares them
4. **Consistent filter design** — one mechanism: Kotlin snapshot → primitive fields over JNI → `Transport::new_from_fields()` on Rust side (works because `zenoh-jni` has `internal` feature flag)
5. **Test plan** — `ConnectivityTest.kt` with 9 test cases covering: transports list, links list, filtered links, transport events, link events, filtered link events, history, undeclare, empty results

## Architecture

3-layer stack: `SessionInfo.kt` → `Session.kt` (strongDeclarations) → `JNIConnectivity.kt` → `connectivity.rs`

## Key Design Decisions

- **Callback-only public API** (not Handler/Channel overloads): justified by `MatchingListener` precedent, which is the closest analog for session-scoped event listeners
- **Separate `JNIConnectivity` class + `connectivity.rs`** (not extending `JNISession`/`session.rs`): complexity of callback-based listeners warrants separation; existing session.rs has only synchronous getters
- **Transport filter via primitives** (not raw pointer): Transport is a pure snapshot on Kotlin side; reconstruction in Rust via `new_from_fields()` is clean and avoids pointer lifecycle issues
- **strongDeclarations** for event listeners (same as Subscribers/Queryables): listeners are session-scoped and should survive until explicitly undeclared or session closes

## Full Plan File Location

`/data/home/skynet/.claude/plans/nifty-sparking-cat.md`

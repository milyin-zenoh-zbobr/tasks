The plan is complete. Here's a summary of what was designed:

## Connectivity API Implementation Plan

**What's being added:** Transport-level and link-level network introspection to zenoh-kotlin, matching the Rust API (`session.info().transports/links/transport_events_listener/link_events_listener`) and following the same pattern as the zenoh-go PR #17.

**Closest analog in codebase:** `MatchingListener` — callback-based listener registered via JNI with foreground (`undeclare()`) and background variants.

**Key design decisions:**

1. **New `io.zenoh.connectivity` package** with 6 files: `Transport`, `Link`, `TransportEvent`, `LinkEvent`, `TransportEventsListener`, `LinkEventsListener` data/listener classes — all `@Unstable`

2. **JNI callback interfaces** passing flat primitives: transport events get `(kind, zidBytes, whatAmI, isQos, isMulticast)`; link events get all link fields with `-1` sentinels for absent optionals and pipe-joined `interfaces` string

3. **New Rust file `zenoh-jni/src/connectivity.rs`** with JNI functions for: `getTransports`, `getLinks`, `declareTransportEventsListener`, `declareBackgroundTransportEventsListener`, `declareLinkEventsListener`, `declareBackgroundLinkEventsListener`, plus `freePtrViaJNI` for both listener types

4. **Extensions to `JNISession.kt` and `SessionInfo.kt`** to expose the new API

5. **`ConnectivityTest.kt`** testing transports list, links list, event callbacks, and background variants
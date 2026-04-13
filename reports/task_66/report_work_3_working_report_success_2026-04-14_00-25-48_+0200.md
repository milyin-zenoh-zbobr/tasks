# Connectivity API Implementation for zenoh-kotlin

## Summary

Implemented the full connectivity API for zenoh-kotlin (issue #647), providing Kotlin/JNI bindings for zenoh's unstable Rust connectivity API.

## What Was Implemented

### New Kotlin Files

**`io/zenoh/connectivity/`**
- `Transport.kt` — `@Unstable data class`: `zid: ZenohId, whatAmI: WhatAmI, isQos: Boolean, isMulticast: Boolean`
- `Link.kt` — `@Unstable data class`: src/dst/group locators, mtu, interfaces, auth, priority/reliability
- `TransportEvent.kt` — `@Unstable data class`: `kind: SampleKind, transport: Transport`
- `LinkEvent.kt` — `@Unstable data class`: `kind: SampleKind, link: Link`
- `TransportEventsListener.kt` — implements `SessionDeclaration, AutoCloseable`
- `LinkEventsListener.kt` — same pattern

**`io/zenoh/handlers/`**
- `TransportEventsCallback.kt`, `TransportEventsHandler.kt`, `TransportEventsChannelHandler.kt`
- `LinkEventsCallback.kt`, `LinkEventsHandler.kt`, `LinkEventsChannelHandler.kt`

**`io/zenoh/jni/callbacks/`**
- `JNITransportSnapshotCallback.kt`, `JNILinkSnapshotCallback.kt`
- `JNITransportEventsCallback.kt`, `JNILinkEventsCallback.kt`

**`io/zenoh/jni/`**
- `JNITransportEventsListener.kt`, `JNILinkEventsListener.kt`

### Modified Kotlin Files

**`JNISession.kt`** — Added wrapper methods (`getTransports`, `getLinks`, `declareTransportEventsListener`, `declareBackgroundTransportEventsListener`, `declareLinkEventsListener`, `declareBackgroundLinkEventsListener`) + external function declarations.

**`Session.kt`** — Added internal delegation methods for all connectivity operations; foreground listeners registered in `strongDeclarations`.

**`session/SessionInfo.kt`** — Complete rewrite with full connectivity API: `transports()`, `links(transport?)`, 6 overloads each for `declareTransportEventsListener`/`declareLinkEventsListener` (callback/handler/channel × foreground/background).

### New Rust File

**`zenoh-jni/src/connectivity.rs`** — 8 JNI functions:
- `getTransportsViaJNI` — sync snapshot, callback per transport
- `getLinksViaJNI` — sync snapshot with optional transport filter, callback per link
- `declareTransportEventsListenerViaJNI` — foreground, returns `Arc<TransportEventsListener<()>>` raw ptr
- `declareBackgroundTransportEventsListenerViaJNI` — background, void
- `declareLinkEventsListenerViaJNI` — foreground with optional transport filter
- `declareBackgroundLinkEventsListenerViaJNI` — background
- `JNITransportEventsListener_freePtrViaJNI` — `Arc::from_raw` drop
- `JNILinkEventsListener_freePtrViaJNI` — same

Async callbacks use `GlobalRef + Arc<JavaVM> + attach_current_thread_as_daemon` pattern. Transport filter reconstructed via `Transport::new_from_fields()` (requires `internal` feature, already enabled).

**`zenoh-jni/src/lib.rs`** — Added `mod connectivity;`

### Tests

**`ConnectivityTest.kt`** — 8 tests:
- `testTransportsList` — two peer sessions, asserts transports() non-empty
- `testLinksListNoFilter` — asserts links() non-empty with valid src/dst
- `testLinksListWithTransportFilter` — filters by Transport, asserts only matching links
- `testTransportEventsListenerOpenClose` — channel receives PUT on connect, DELETE on disconnect
- `testTransportEventsHistoryDelivery` — history=true delivers existing transport as PUT immediately
- `testLinkEventsListenerOpenClose` — channel receives PUT/DELETE for link lifecycle
- `testLinkEventsListenerWithTransportFilter` — history=true filtered to specific transport
- `testBackgroundTransportEventsListener` / `testBackgroundLinkEventsListener` — background variants fire

## Test Results

- All 8 new ConnectivityTest tests: PASSED
- Full regression: 122 tests executed, 0 failures, BUILD SUCCESSFUL

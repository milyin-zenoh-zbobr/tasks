All work is complete. Here's a summary of what was implemented:

**Rust (`zenoh-jni/src/connectivity.rs`)** — 8 JNI functions covering snapshot queries (transports, links) and event listener declaration (foreground/background for both transport and link events), plus two `freePtrViaJNI` functions for resource cleanup. All 6 compilation errors were fixed: corrected import paths (`zenoh::session::*`), fixed `WhatAmI::try_from` error formatting, fixed `JObject::from` type inference, and fixed temporary lifetime issues with `session.info()`.

**Kotlin** — New data classes (`Transport`, `Link`, `TransportEvent`, `LinkEvent`), listener classes, handler/callback/channel handler interfaces for both event types, JNI adapter classes, and a complete `SessionInfo` API with 12 overloaded methods (callback/handler/channel × foreground/background × transport/link).

**Tests** — 8 tests in `ConnectivityTest.kt` covering all API surface: snapshot queries, event listeners with open/close detection, history delivery, transport filters, and background listeners.

**Results**: All 8 new tests pass, full regression of 122 tests passes with no failures.
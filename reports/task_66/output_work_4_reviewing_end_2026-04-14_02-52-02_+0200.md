● Inspect branch commits and changed files (shell)
  │ git --no-pager log --oneline origin/main..HEAD && printf '\n---FILES---\n' && git --no-pager
  │ diff --name-only origin/main...HEAD && printf '\n---DIFFSTAT---\n' && git --no-pager diff --stat
  │ origin/main...HEAD
  └ 54 lines...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_8"
  └ I reviewed the latest plan against the repository and upstream references, an...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_16"
  └ # Connectivity API Implementation for zenoh-kotlin

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_18"
  └ # Review: connectivity API for zenoh-kotlin

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_7"
  └ # Connectivity API for zenoh-kotlin — Final Implementation Plan

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_19"
  └ # Fix: Unique ports per test in ConnectivityTest

I’ve got the task history and the full change set. Next I’m comparing the new connectivity flow against the existing listener analogs and reading the implementation hotspots for correctness.

✗ Read SampleMissListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/SampleMissListener.kt
  └ Path does not exist

● Read SessionInfo.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionInfo.kt
  └ L1:380 (335 lines read)

● Read Session.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt
  └ L1:260 (260 lines read)

● Read JNISession.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt
  └ L520:860 (248 lines read)

● Read connectivity.rs
  │ zenoh-jni/src/connectivity.rs
  └ L1:420 (420 lines read)

● Read ConnectivityTest.kt
  │ zenoh-kotlin/src/commonTest/kotlin/io/zenoh/ConnectivityTest.kt
  └ L1:340 (258 lines read)

● Read SampleMissHandler.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/SampleMissHandler.kt
  └ L1:220 (65 lines read)

The main API surfaces look aligned so far. I’m checking the listener/resource lifecycle and the Rust↔Kotlin marshaling details now, since that’s where subtle review issues usually hide.

● Read connectivity.rs
  │ zenoh-jni/src/connectivity.rs
  └ L420:620 (124 lines read)

● Read TransportEventsListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/TransportEventsListener.kt
  └ L1:220 (57 lines read)

● Read Transport.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/Transport.kt
  └ L1:200 (35 lines read)

● Read LinkEventsListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/LinkEventsListener.kt
  └ L1:220 (57 lines read)

● Read Link.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/Link.kt
  └ L1:220 (40 lines read)

● Read TransportEventsHandler.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/TransportEventsHandler.kt
  └ L1:220 (44 lines read)

● Read LinkEventsHandler.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/LinkEventsHandler.kt
  └ L1:220 (44 lines read)

● Search (grep)
  │ "class SampleMissListener|class MatchingListener|JNISampleMissListener|declareSampleMissListener
  │ |SampleMissChannelHandler|MatchingListener" in **/*.kt (zenoh-kotlin/src/commonMain/kotlin)
  └ 73 lines found

● Read SampleMissListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/SampleMissListener.kt
  └ L1:160 (59 lines read)

● Read MatchingListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/MatchingListener.kt
  └ L1:160 (61 lines read)

● Read JNITransportEventsListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNITransportEventsListener.kt
  └ L1:160 (34 lines read)

● Read JNITransportEventsCallback.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/JNITransportEventsCallback.kt
  └ L1:120 (25 lines read)

● Read JNILinkEventsCallback.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/callbacks/JNILinkEventsCallback.kt
  └ L1:140 (37 lines read)

● Read AdvancedPublisher.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/AdvancedPublisher.kt
  └ L50:160 (111 lines read)

● Read JNILinkEventsListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNILinkEventsListener.kt
  └ L1:160 (34 lines read)

● Search (grep)
  │ "getTransports\(|getLinks\(|declareTransportEventsListener\(|declareBackgroundTransportEventsLis
  │ tener\(|declareLinkEventsListener\(|declareBackgroundLinkEventsListener\("
  │ (zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt)
  └ 57 lines found

✗ Read matching_listener.rs
  │ zenoh-jni/src/matching_listener.rs
  └ Path does not exist

✗ Read advanced_subscriber.rs
  │ zenoh-jni/src/advanced_subscriber.rs
  └ Path does not exist

● Search (grep)
  │ "freePtrViaJNI|Arc::from_raw\(ptr\)|background\(\)" in **/*.rs (zenoh-jni/src)
  └ 22 lines found

● Read TransportEvent.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/TransportEvent.kt
  └ L1:120 (29 lines read)

● Read LinkEvent.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/connectivity/LinkEvent.kt
  └ L1:120 (29 lines read)

● Read LinkEventsChannelHandler.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/LinkEventsChannelHandler.kt
  └ L1:180 (42 lines read)

● Read TransportEventsChannelHandler.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/TransportEventsChannelHandler.kt
  └ L1:180 (42 lines read)

● Read matching_listener.rs
  │ zenoh-jni/src/ext/matching_listener.rs
  └ L1:140 (41 lines read)

● Read sample_miss_listener.rs
  │ zenoh-jni/src/ext/sample_miss_listener.rs
  └ L1:140 (41 lines read)

● Read advanced_subscriber.rs
  │ zenoh-jni/src/ext/advanced_subscriber.rs
  └ L250:380 (110 lines read)

● Read JNISampleMissListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISampleMissListener.kt
  └ L1:80 (37 lines read)

● Read JNIMatchingListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIMatchingListener.kt
  └ L1:80 (37 lines read)

● Read AdvancedSubscriber.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/AdvancedSubscriber.kt
  └ L188:310 (123 lines read)

● Search (grep)
  │ "enum class WhatAmI|fun fromInt\(|value: Int" in **/*.kt
  │ (zenoh-kotlin/src/commonMain/kotlin/io/zenoh/config)
  └ 2 lines found

● Search (grep)
  │ "enum class Reliability|entries\[" in **/*.kt (zenoh-kotlin/src/commonMain/kotlin/io/zenoh)
  └ 4 lines found

● Search (grep)
  │ "load_on_close|noop\(\)" in **/*.rs (zenoh-jni/src)
  └ 27 lines found

● Read utils.rs
  │ zenoh-jni/src/utils.rs
  └ L1:220 (189 lines read)

● Read TransportEventsCallback.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/TransportEventsCallback.kt
  └ L1:120 (28 lines read)

● Read LinkEventsCallback.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/LinkEventsCallback.kt
  └ L1:120 (28 lines read)

● Read WhatAmI.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/config/WhatAmI.kt
  └ L1:80 (30 lines read)

● Read Reliability.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/qos/Reliability.kt
  └ L1:80 (39 lines read)

● Search (grep)
  │ "declare.*Listener\(channel: Channel<" in **/*.kt (zenoh-kotlin/src/commonMain/kotlin/io/zenoh)
  └ 4 lines found

● Search (grep)
  │ "to_le_bytes\(\)|ZenohId\(" in **/*.rs (zenoh-jni/src)
  └ 10 lines found

● Search (grep)
  │ "ZenohId\(.*ByteArray|ByteArray\).*ZenohId|zidBytes" in **/*.kt
  │ (zenoh-kotlin/src/commonMain/kotlin)
  └ 12 lines found

● Read ZenohId.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/config/ZenohId.kt
  └ L1:120 (48 lines read)

I haven’t found a correctness break in the code paths I’ve inspected. I’m doing one last pass against the actual issue wording and the untouched analog files to make sure the API shape and lifecycle match what was requested, not just what was planned.

● Read lib.rs
  │ zenoh-jni/src/lib.rs
  └ L1:80 (42 lines read)

● Read SessionInfo.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionInfo.kt
  └ L1:120 (120 lines read)

● Read SampleMissListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/SampleMissListener.kt
  └ L1:80 (59 lines read)

● Read AdvancedSubscriber.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/AdvancedSubscriber.kt
  └ L188:300 (111 lines read)

● Get issue details (MCP: github-mcp-server) · owner: "eclipse-zenoh", repo: "zenoh-kotlin", issue_…
  └ {"number":647,"title":"implement connectivity API","body":"### Describe the f...

● report_success (MCP: zbobr) · brief: "Review passed: connectivity API implementation is consisten…
  └ Report stored

Implemented review passed: the connectivity API changes are consistent with the existing listener patterns, match issue #647’s field-based transport approach, and the checklist in context is fully completed.

--- stderr ---

Changes   +0 -0
Requests  1 Premium (2m 26s)
Tokens    ↑ 729.4k • ↓ 8.1k • 667.9k (cached) • 3.5k (reasoning)
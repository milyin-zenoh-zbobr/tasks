I’m pulling the revised plan and checking the codebase against its assumptions before judging whether it’s implementation-ready.

● Search (grep)
  │ "TransportManager|open_transport|close_transport|ZenohIdProto|LinkState|linkstate|WhatAmI|Transp
  │ ortUnicast" in **/*.{kt,rs}
  └ 25 lines found

● Search (glob)
  │ "**/*.{kt,rs}"
  └ 151 files found

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_3"
  └ # Connectivity API for zenoh-kotlin — Implementation Plan

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_2"
  └ The plan has the right high-level intent — snapshot transport/link state in n...

The revised plan fixed the earlier big mismatches; I’m checking whether it now matches the actual listener and JNI patterns in this repo, and whether any hidden gaps remain.

● Read SessionInfo.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionInfo.kt
  └ L1:260 (45 lines read)

● Read Session.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt
  └ L1:260 (260 lines read)

● Read JNISession.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt
  └ L1:360 (360 lines read)

● Read MatchingListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/MatchingListener.kt
  └ L1:220 (61 lines read)

● Read SampleMissListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/SampleMissListener.kt
  └ L1:240 (59 lines read)

● Read MatchingHandler.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/MatchingHandler.kt
  └ L1:220 (64 lines read)

● Read SampleMissHandler.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/SampleMissHandler.kt
  └ L1:220 (65 lines read)

● Read matching_listener.rs
  │ zenoh-jni/src/ext/matching_listener.rs
  └ L1:320 (41 lines read)

● Read sample_miss_listener.rs
  │ zenoh-jni/src/ext/sample_miss_listener.rs
  └ L1:340 (41 lines read)

● Read JNIMatchingListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIMatchingListener.kt
  └ L1:160 (37 lines read)

● Read JNISampleMissListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISampleMissListener.kt
  └ L1:160 (37 lines read)

● Read session.rs
  │ zenoh-jni/src/session.rs
  └ L1:260 (260 lines read)

● Read lib.rs
  │ zenoh-jni/src/lib.rs
  └ L1:220 (41 lines read)

● Search (grep)
  │ "declareMatchingListener|declareSampleMissListener|background\(\)" in **/*.{kt,rs}
  └ 25 lines found

● Read AdvancedPublisher.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/AdvancedPublisher.kt
  └ L1:170 (170 lines read)

● Read AdvancedSubscriber.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/AdvancedSubscriber.kt
  └ L160:290 (131 lines read)

● Read JNIAdvancedPublisher.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedPublisher.kt
  └ L1:150 (124 lines read)

● Read JNIAdvancedSubscriber.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedSubscriber.kt
  └ L90:210 (79 lines read)

● Read advanced_publisher.rs
  │ zenoh-jni/src/ext/advanced_publisher.rs
  └ L100:240 (141 lines read)

● Read advanced_subscriber.rs
  │ zenoh-jni/src/ext/advanced_subscriber.rs
  └ L230:360 (130 lines read)

● Read SessionDeclaration.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionDeclaration.kt
  └ L1:120 (33 lines read)

● Read Annotations.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/annotations/Annotations.kt
  └ L1:120 (23 lines read)

● Read SessionInfoTest.kt
  │ zenoh-kotlin/src/commonTest/kotlin/io/zenoh/SessionInfoTest.kt
  └ L1:220 (119 lines read)

● Read ChannelHandler.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/ChannelHandler.kt
  └ L1:140 (43 lines read)

● Read SampleMissChannelHandler.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/SampleMissChannelHandler.kt
  └ L1:140 (55 lines read)

● Search (grep)
  │ "fun getPeersId|fun getRoutersId|fun zid\(|SessionInfo\(" in **/*.kt
  │ (zenoh-kotlin/src/commonMain/kotlin/io/zenoh)
  └ 7 lines found

● Search (grep)
  │ "peers|routers|zid" (zenoh-jni/src/session.rs)
  └ 10 lines found

● Read ZenohId.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/config/ZenohId.kt
  └ L1:180 (48 lines read)

● Read JNISession.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt
  └ L380:450 (71 lines read)

● Read Reliability.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/qos/Reliability.kt
  └ L1:160 (39 lines read)

● Read Session.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt
  └ L1170:1210 (40 lines read)

I’ve confirmed the Kotlin-side listener conventions. The remaining question is whether the revised plan’s Rust-side filter/marshalling assumptions really match upstream zenoh’s unstable connectivity API.

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh transport_events_listener languag…
  └ Output too large to read at once (46.2 KB). Saved to: /tmp/1776110577193-copi...

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh "links().transport" language:Rust…
  └ {"total_count":1,"incomplete_results":false,"items":[{"name":"info_links.rs",...

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh link_events_listener language:Rus…
  └ Output too large to read at once (27.7 KB). Saved to: /tmp/1776110577953-copi...

● Web Search (MCP: github-mcp-server) · zenoh Rust transport_events_listener link_events_listener l…
  └ {"type":"text","text":{"value":"Let's break down the main aspects of Zenoh Ru...

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh "pub struct Link" path:zenoh/src …
  └ {"total_count":2,"incomplete_results":false,"items":[{"name":"info.rs","path"...

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh "pub struct Transport" path:zenoh…
  └ {"total_count":2,"incomplete_results":false,"items":[{"name":"info.rs","path"...

● Get file or directory contents (MCP: github-mcp-server) · zenoh/src/api/builders/info_links.rs · …
  └ successfully downloaded text file (SHA: dffaa564ce411a3c2867dd9c009c3228ba25f...

● Get file or directory contents (MCP: github-mcp-server) · zenoh/src/api/info.rs · owner: "eclipse…
  └ successfully downloaded text file (SHA: 6184b8e1eb0113d905969992994e0b48f2b1a...

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh "declare_transport_links_listener…
  └ {"total_count":3,"incomplete_results":false,"items":[{"name":"session.rs","pa...

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh "new_from_fields" "Transport" pat…
  └ {"total_count":1,"incomplete_results":false,"items":[{"name":"info.rs","path"...

● Get file or directory contents (MCP: github-mcp-server) · zenoh/src/api/builders/info_transport.r…
  └ successfully downloaded text file (SHA: 0dc6057966b6e5c757331a1d6b2c198f8fb63...

The upstream source exposed one subtle but important issue: `Transport` is **not** uniquely identified by `zid`; zenoh can have multiple transports to the same peer. I’m checking whether the plan’s transport-filter design is therefore fundamentally unsafe in this repo.

● Search (glob)
  │ "**/Cargo.toml"
  └ 1 file found

● Search (grep)
  │ "shared-memory|zenoh-ext|unstable|features" in **/Cargo.toml
  └ 6 lines found

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh "declare_transport_links_listener…
  └ {"total_count":0,"incomplete_results":false}

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh "declare_transport_events_listene…
  └ {"total_count":0,"incomplete_results":false}

● Read Cargo.toml
  │ zenoh-jni/Cargo.toml
  └ L1:120 (55 lines read)

● Get file or directory contents (MCP: github-mcp-server) · zenoh/src/api/session.rs · owner: "ecli…
  └ Output too large to read at once (133.6 KB). Saved to: /tmp/1776110644096-cop...

● Search (grep)
  │ "declare_transport_events_listener_inner|declare_transport_links_listener_inner|transport_events
  │ _listener|link_events_listener" (/tmp/1776110644096-copilot-tool-output-vj2alg.txt)
  └ 20 lines found

● Search (grep)
  │ "shared-memory" (/tmp/1776110644096-copilot-tool-output-vj2alg.txt)
  └ 9 lines found

● Search (grep)
  │ "struct TransportEventsListenerState|struct LinkEventsListenerState"
  │ (/tmp/1776110644096-copilot-tool-output-vj2alg.txt)
  └ 2 lines found

● Search (grep)
  │ "get_transports|get_links" (/tmp/1776110644096-copilot-tool-output-vj2alg.txt)
  └ 2 lines found

● Read 1776110644096-copilot-tool-output-vj2alg.txt
  │ /tmp/1776110644096-copilot-tool-output-vj2alg.txt
  └ L2260:2375 (116 lines read)

● Read 1776110644096-copilot-tool-output-vj2alg.txt
  │ /tmp/1776110644096-copilot-tool-output-vj2alg.txt
  └ L2375:2425 (51 lines read)

● Read 1776110644096-copilot-tool-output-vj2alg.txt
  │ /tmp/1776110644096-copilot-tool-output-vj2alg.txt
  └ L120:160 (41 lines read)

● Read 1776110644096-copilot-tool-output-vj2alg.txt
  │ /tmp/1776110644096-copilot-tool-output-vj2alg.txt
  └ L2418:2434 (17 lines read)

I found a second likely architectural gap: the plan assumes `Transport.isShm` is always available, but upstream only exposes that field behind Rust’s `shared-memory` feature. This repo doesn’t obviously enable that feature today.

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh "default = [" path:Cargo.toml lan…
  └ {"total_count":0,"incomplete_results":false}

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh "shared-memory" path:Cargo.toml l…
  └ {"total_count":0,"incomplete_results":false}

● Get file or directory contents (MCP: github-mcp-server) · zenoh/Cargo.toml · owner: "eclipse-zeno…
  └ successfully downloaded text file (SHA: b476f5ea04dc5115c7a5252ecec1c07c67ce1...

● Get issue details (MCP: github-mcp-server) · owner: "eclipse-zenoh", repo: "zenoh-kotlin", issue_…
  └ []

● Get issue details (MCP: github-mcp-server) · owner: "eclipse-zenoh", repo: "zenoh-kotlin", issue_…
  └ {"number":647,"title":"implement connectivity API","body":"### Describe the f...

The issue text added one more constraint: it explicitly asks for a Go-binding-like approach and says to “store fields in native structure.” I’m checking whether the plan’s proposed JNI shape is aligned enough, or if it still drifts from that direction.

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go "type Transport" path:**/*.go …
  └ {"total_count":0,"incomplete_results":false}

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go transport_events_listener OR l…
  └ {"total_count":0,"incomplete_results":false}

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go "type Link" path:**/*.go langu…
  └ {"total_count":0,"incomplete_results":false}

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go connectivity TransportEvent Li…
  └ {"total_count":1,"incomplete_results":false,"items":[{"name":"z_info.go","pat...

✗ Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go "GetLinks" language:Go · query…
  └ MCP server 'github-mcp-server': failed to search code with query 'repo:eclipse-zenoh/zenoh-go
    "GetLinks" language:Go': GET https://api.github.com/search/code?page=1&per_page=20&q=repo%3Aecli
    pse-zenoh%2Fzenoh-go+%22GetLinks%22+language%3AGo: 403 API rate limit exceeded for user ID
    1909657. If you reach out to GitHub Support for help, please include the request ID
    D254:31D0F9:41B9CB3:47EBC12:69DD4C80 and timestamp 2026-04-13 20:05:27 UTC. For more on scraping
    GitHub and how it may affect your rights, please review our Terms of Service
    (https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) [rate reset in
    34s]

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go TransportEventsListener langua…
  └ {"total_count":3,"incomplete_results":false,"items":[{"name":"transport.go","...

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go "GetTransports" language:Go · …
  └ {"total_count":0,"incomplete_results":false}

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go LinkEventsListener language:Go…
  └ {"total_count":3,"incomplete_results":false,"items":[{"name":"link.go","path"...

● Get file or directory contents (MCP: github-mcp-server) · zenoh/link.go · owner: "eclipse-zenoh",…
  └ successfully downloaded text file (SHA: 123048bc7e367d16bcf96152ac82f381c3e00...

● Get file or directory contents (MCP: github-mcp-server) · tests/connectivity_test.go · owner: "ec…
  └ successfully downloaded text file (SHA: edaf9ee548dca8b0e1be76125a56e89165865...

● Get file or directory contents (MCP: github-mcp-server) · zenoh/transport.go · owner: "eclipse-ze…
  └ successfully downloaded text file (SHA: d9591ee8b946fb97f9386dbeef1a68ca2a1ba...

I found two blocking design issues in the revised plan. The overall direction now matches the repo much better, but it still isn’t safe to hand off unchanged.

● report_failure (MCP: zbobr) · brief: "Revised connectivity plan is close, but still has two block…
  └ Report stored

Rejected the revised plan. It’s close, but it still has two blocking design problems: it treats a transport filter as if `zid` were a unique transport identity, and it assumes `isShm` exists unconditionally even though this repo does not enable upstream zenoh’s `shared-memory` feature.

I reported the specific fixes needed: use a full reconstructable transport snapshot/native transport representation for `links(transport)` and filtered link listeners, resolve the `isShm` feature mismatch explicitly, and correct the invalid `cargo build --features unstable` verification step.

--- stderr ---

Changes   +0 -0
Requests  1 Premium (5m 0s)
Tokens    ↑ 1.6m • ↓ 9.1k • 1.5m (cached) • 3.3k (reasoning)
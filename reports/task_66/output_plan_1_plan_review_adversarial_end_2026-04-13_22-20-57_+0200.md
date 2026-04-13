I’m pulling the latest plan and checking the codebase assumptions against the actual Kotlin/JNI surfaces before I judge whether it’s implementable.

● Search (grep)
  │ "(scout|SessionInfo|ZenohId|WhatAmI|Locator|Hello|ScoutingConfig|Scout)" in **/*.{kt,java,rs,md}
  └ 10 lines found

● Search (glob)
  │ "**/*.{kt,java,rs}"
  └ 151 files found

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_5"
  └ # Connectivity API for zenoh-kotlin — Implementation Plan

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_4"
  └ The revised plan fixes the earlier Kotlin API-shape problems and is much clos...

I found the latest plan and the prior objections. Now I’m checking whether the proposed JNI/Kotlin patterns really match what this repo already does.

● Read Session.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt
  └ 1 line read

● Read session.rs
  │ zenoh-jni/src/session.rs
  └ 1 line read

● Read SampleMissListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/SampleMissListener.kt
  └ 59 lines read

● Read SampleMissCallback.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/SampleMissCallback.kt
  └ 31 lines read

● Read SampleMissHandler.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/SampleMissHandler.kt
  └ 65 lines read

● Read SampleMissChannelHandler.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/SampleMissChannelHandler.kt
  └ 55 lines read

● Read JNISampleMissListener.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISampleMissListener.kt
  └ 37 lines read

● Read SessionInfo.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionInfo.kt
  └ 45 lines read

● Read JNISession.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt
  └ 552 lines read

● Read Cargo.toml
  │ zenoh-jni/Cargo.toml
  └ 55 lines read

● Read matching_listener.rs
  │ zenoh-jni/src/ext/matching_listener.rs
  └ 41 lines read

● Read sample_miss_listener.rs
  │ zenoh-jni/src/ext/sample_miss_listener.rs
  └ 41 lines read

● Read lib.rs
  │ zenoh-jni/src/lib.rs
  └ 41 lines read

● Get issue details (MCP: github-mcp-server) · owner: "eclipse-zenoh", repo: "zenoh-kotlin", issue_…
  └ {"number":647,"title":"implement connectivity API","body":"### Describe the f...

The repo patterns mostly line up with the plan so far. I’m drilling into the exact listener overload shape and the existing native pointer-lifecycle conventions, since that’s where these plans usually go wrong.

● Search (grep)
  │ "into_raw|from_raw|mem::forget|OwnedObject|background\(\)\.wait|history\(|GlobalRef|JavaVM" in
  │ **/*.rs (./zenoh-jni/src)
  └ 133 lines found

● Search (grep)
  │ "declareSampleMissListener|SampleMissListener|declareMatchingListener|getPeersId|getRoutersId|fu
  │ n info\(|class Session" in zenoh-kotlin/src/commonMain/kotlin/**/*.kt
  └ 65 lines found

● Search (grep)
  │ "Transport|Link|transport_events_listener|link_events_listener|links\(|transports\(|is_shm|share
  │ d-memory" in **/*.{rs,toml} (./zenoh-jni)
  └ No matches found

I’m checking the upstream/go analog too, because the issue explicitly asks to mirror that approach and that can invalidate an otherwise-plausible JNI design.

● Read AdvancedSubscriber.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/AdvancedSubscriber.kt
  └ L180:320 (141 lines read)

● Read Session.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt
  └ L1060:1210 (150 lines read)

● Read JNIAdvancedSubscriber.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNIAdvancedSubscriber.kt
  └ L90:170 (79 lines read)

● Read advanced_publisher.rs
  │ zenoh-jni/src/ext/advanced_publisher.rs
  └ L110:190 (81 lines read)

● Read advanced_subscriber.rs
  │ zenoh-jni/src/ext/advanced_subscriber.rs
  └ L240:330 (91 lines read)

✗ Fetching web content https://raw.githubusercontent.com/eclipse-zenoh/zenoh-go/main/internal/conne…
  └ Error: Failed to fetch
    https://raw.githubusercontent.com/eclipse-zenoh/zenoh-go/main/internal/connectivity.go - status
    code 404

● Fetching web content https://raw.githubusercontent.com/eclipse-zenoh/zenoh/main/zenoh/src/api/inf…
  └ Content type text/plain; charset=utf-8 cannot be simplified to markdown. Here...

The upstream Rust API confirms the feature-gating and transport semantics. I’m locating the Go binding’s actual transport round-trip design now, since the issue points to it directly.

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go toCPtr connectivity transport …
  └ {"total_count":0,"incomplete_results":false}

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go TransportEvent LinkEvent conne…
  └ {"total_count":1,"incomplete_results":false,"items":[{"name":"z_info.go","pat...

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go internal.Transport LinkListene…
  └ {"total_count":0,"incomplete_results":false}

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go LinkEvent language:Go · query:…
  └ {"total_count":3,"incomplete_results":false,"items":[{"name":"link.go","path"...

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go transports() language:Go · que…
  └ {"total_count":3,"incomplete_results":false,"items":[{"name":"z_info.go","pat...

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go newFromCPtr toCPtr language:Go…
  └ {"total_count":0,"incomplete_results":false}

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh-go TransportEvent language:Go · q…
  └ {"total_count":3,"incomplete_results":false,"items":[{"name":"transport.go","...

● Get file or directory contents (MCP: github-mcp-server) · tests/connectivity_test.go · owner: "ec…
  └ successfully downloaded text file (SHA: edaf9ee548dca8b0e1be76125a56e89165865...

● Get file or directory contents (MCP: github-mcp-server) · zenoh/link.go · owner: "eclipse-zenoh",…
  └ successfully downloaded text file (SHA: 123048bc7e367d16bcf96152ac82f381c3e00...

● Get file or directory contents (MCP: github-mcp-server) · zenoh/transport.go · owner: "eclipse-ze…
  └ successfully downloaded text file (SHA: d9591ee8b946fb97f9386dbeef1a68ca2a1ba...

● Get file or directory contents (MCP: github-mcp-server) · examples/z_info/z_info.go · owner: "ecl…
  └ successfully downloaded text file (SHA: d5f0ae6d1edb3fd5e7e9a59403414561da67c...

I’ve confirmed the Go binding reconstructs transports from snapshot fields rather than keeping borrowed/native transport identities around. I’m checking whether upstream Rust supports the same reconstruction path; if it does, that makes the plan’s pointer design look needlessly risky.

● Fetching web content https://raw.githubusercontent.com/eclipse-zenoh/zenoh/main/zenoh/src/api/ses…
  └ Content type text/plain; charset=utf-8 cannot be simplified to markdown. Here...

● Fetching web content https://raw.githubusercontent.com/eclipse-zenoh/zenoh/main/zenoh/src/api/bui…
  └ Content type text/plain; charset=utf-8 cannot be simplified to markdown. Here...

● Fetching web content https://raw.githubusercontent.com/eclipse-zenoh/zenoh/main/zenoh/src/api/bui…
  └ Content type text/plain; charset=utf-8 cannot be simplified to markdown. Here...

Upstream Rust does support value-based transport filters, not pointer identity, which is important here. I’m checking the exact internal helper next to see whether the plan’s raw-pointer round-trip is not just different, but actually the wrong abstraction for this codebase.

● Fetching web content https://raw.githubusercontent.com/eclipse-zenoh/zenoh/main/zenoh/src/api/con…
  └ Content type text/plain; charset=utf-8 cannot be simplified to markdown. Here...

✗ Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh "declare_transport_links_listener…
  └ MCP server 'github-mcp-server': failed to search code with query 'repo:eclipse-zenoh/zenoh
    "declare_transport_links_listener_inner" language:Rust': GET
    https://api.github.com/search/code?page=1&per_page=20&q=repo%3Aeclipse-zenoh%2Fzenoh+%22declare_
    transport_links_listener_inner%22+language%3ARust: 403 API rate limit exceeded for user ID
    1909657. If you reach out to GitHub Support for help, please include the request ID
    EC62:1D9219:44FAF84:4B41816:69DD4F9E and timestamp 2026-04-13 20:18:58 UTC. For more on scraping
    GitHub and how it may affect your rights, please review our Terms of Service
    (https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) [rate reset in
    23s]

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh "new_from_fields(" language:Rust …
  └ {"total_count":1,"incomplete_results":false,"items":[{"name":"info.rs","path"...

● Search code (MCP: github-mcp-server) · repo:eclipse-zenoh/zenoh "get_links(" "transport: Option<T…
  └ {"total_count":2,"incomplete_results":false,"items":[{"name":"info_links.rs",...

I’ve got enough to suspect the plan over-engineers transport identity. I’m pulling one more upstream slice to see whether filtering is field-based all the way through, because that would make the raw-pointer design a real architectural miss, not just a different implementation choice.

● Inspect upstream connectivity broadcast logic (shell)
  │ curl -L --silent
  │ https://raw.githubusercontent.com/eclipse-zenoh/zenoh/main/zenoh/src/api/connectivity.rs | rg -n
  │ "broadcast_link_event|broadcast_transport_event|Transport::new|Link::new"
  └ 2 lines...

● Inspect upstream session connectivity internals (shell)
  │ curl -L --silent
  │ https://raw.githubusercontent.com/eclipse-zenoh/zenoh/main/zenoh/src/api/session.rs | rg -n
  │ "declare_transport_links_listener_inner|get_links\(|broadcast_link_event|broadcast_transport_eve
  │ nt|transport ==|transport\.as_ref|LinkEventsListenerState"
  └ 2 lines...

The shell here doesn’t have `rg`, so I’m falling back to `grep` for the last upstream confirmation pass.

● Inspect upstream connectivity broadcast logic (shell)
  │ curl -L --silent
  │ https://raw.githubusercontent.com/eclipse-zenoh/zenoh/main/zenoh/src/api/connectivity.rs | grep
  │ -nE "broadcast_link_event|broadcast_transport_event|Transport::new|Link::new"
  └ 6 lines...

● Inspect upstream session connectivity internals (shell)
  │ curl -L --silent
  │ https://raw.githubusercontent.com/eclipse-zenoh/zenoh/main/zenoh/src/api/session.rs | grep -nE
  │ "declare_transport_links_listener_inner|get_links\(|broadcast_link_event|broadcast_transport_eve
  │ nt|transport ==|transport\.as_ref|LinkEventsListenerState"
  └ 14 lines...

● Read upstream link listener implementation (shell)
  │ curl -L --silent
  │ https://raw.githubusercontent.com/eclipse-zenoh/zenoh/main/zenoh/src/api/session.rs | sed -n
  │ '2338,2425p'
  └ 89 lines...

● Read upstream transport broadcast implementation (shell)
  │ curl -L --silent
  │ https://raw.githubusercontent.com/eclipse-zenoh/zenoh/main/zenoh/src/api/session.rs | sed -n
  │ '2316,2340p'
  └ 26 lines...

● Read rest of upstream link event filtering (shell)
  │ curl -L --silent
  │ https://raw.githubusercontent.com/eclipse-zenoh/zenoh/main/zenoh/src/api/session.rs | sed -n
  │ '2425,2445p'
  └ 22 lines...

I found a more serious problem than the earlier transport-identity debate: the plan’s own JNI callback shape would produce `Transport` snapshots from events that cannot be reused as transport filters, while the Go/upstream API expects exactly that kind of reusable snapshot. I’m checking one local lifecycle detail before I write up the verdict.

● Read Session.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt
  └ L60:140 (81 lines read)

● Search (grep)
  │ "strongDeclarations|weakDeclarations|undeclare\(|close\(\)|SessionDeclaration"
  │ (./zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt)
  └ 18 lines found

● Read Session.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/Session.kt
  └ L1000:1060 (61 lines read)

● Read SessionDeclaration.kt
  │ zenoh-kotlin/src/commonMain/kotlin/io/zenoh/session/SessionDeclaration.kt
  └ 33 lines read

I’ve finished the review. The plan is close on surface API shape, but it still has blocking architectural problems around transport representation and listener integration.

● report_failure (MCP: zbobr) · brief: "Plan is not ready: the raw-pointer transport design conflic…
  └ Report stored

Reported **failure**: the plan is **not ready**. The main blockers are the raw-pointer `Transport` design, the fact that event-derived `Transport` objects would not be reusable as filters under that design, and missing clarity on session-scoped listener lifecycle integration.

--- stderr ---

Changes   +0 -0
Requests  1 Premium (3m 27s)
Tokens    ↑ 1.2m • ↓ 9.0k • 1.1m (cached) • 3.8k (reasoning)
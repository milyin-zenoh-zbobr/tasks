I’m pulling the approved plan and the full branch diff first so I can review the implementation against the intended analog and scope.

● Show branch commits and changed files (shell)
  │ git --no-pager log --oneline origin/main..HEAD && printf '\n---DIFF---\n' && git --no-pager diff
  │ --stat origin/main...HEAD && printf '\n---FILES---\n' && git --no-pager diff --name-only
  │ origin/main...HEAD
  └ 19 lines...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_10"
  └ ## Plan Summary

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_4"
  └ # Connectivity API Plan — Updated with Matching Listener Analogy

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_11"
  └ # Connectivity API Implementation — Complete

I’ve got the intended analogs. Next I’m reading the new files alongside the existing matching/info patterns to check consistency and look for correctness issues.

● Search (grep)
  │ "func \(s Session\) PeersZId|func \(s Session\) RoutersZId|type
  │ MatchingListener|DeclareBackgroundMatchingListener|DeclareMatchingListener" in *.go (zenoh)
  └ 7 lines found

● Read zenoh_cgo.h
  │ zenoh/zenoh_cgo.h
  └ 253 lines read

● Read connectivity_test.go
  │ tests/connectivity_test.go
  └ 305 lines read

● Read z_info.go
  │ examples/z_info/z_info.go
  └ 112 lines read

● Read matching.go
  │ zenoh/matching.go
  └ 161 lines read

● Read link.go
  │ zenoh/link.go
  └ 321 lines read

● Read transport.go
  │ zenoh/transport.go
  └ 218 lines read

I’ve narrowed this to a few likely review points: ownership/lifetime handling, whether the listener APIs truly mirror the matching-listener pattern, and whether the example/test patterns match existing code.

● Search (glob)
  │ "**/matching_test.go"
  └ 1 file found

● Search (grep)
  │ "func \(session Session\) (PeersZId|RoutersZId)|func \(session \*Session\)
  │ Declare.*Listener|type .*Options struct" in *.go (zenoh)
  └ 36 lines found

● Search (grep)
  │ "z_api_info\.c|z_info\.c"
  └ No matches found

● Search (grep)
  │ "GoStringN\(|z_internal_string_check\(|z_string_array_drop\(|z_.*_clone\(&" in *.go (zenoh)
  └ 25 lines found

● Search (grep)
  │ "type SampleKind|type Reliability|type WhatAmI|NewFifoChannel|Handler\[" in *.go (zenoh)
  └ 20 lines found

✗ Read closure.go
  │ zenoh/internal/closure.go
  └ Path does not exist

● Search (grep)
  │ "z_link_event_kind|z_transport_event_kind|z_declare_link_events_listener|z_info_links|z_info_tra
  │ nsports" in **/*.{h,c,go}
  └ 9 lines found

● Read session.go
  │ zenoh/session.go
  └ L110:180 (43 lines read)

● Read matching_test.go
  │ tests/matching_test.go
  └ 280 lines read

I found one likely ownership issue already and I’m verifying it against existing optional-string handling before I finalize the review.

● Search (grep)
  │ "z_internal_string_check\(&s\).*return """ in *.go (zenoh)
  └ No matches found

● Search (glob)
  │ "zenoh/internal/*.go"
  └ 1 file found

● Search (grep)
  │ "z_info\.go|signal\.Notify\(|Press CTRL-C|Monitoring" in **/*.go (examples)
  └ 30 lines found

● Read config.go
  │ zenoh/config.go
  └ L90:130 (41 lines read)

I found a more important ownership question: the event callbacks clone C-owned transports/links into each event, so I’m checking whether the API exposes a corresponding drop path the same way other value types do.

● Read closures.go
  │ zenoh/internal/closures.go
  └ 54 lines read

● Search (grep)
  │ "type Sample struct|func \(.*\) Drop\(\)|type Query struct|type Reply struct" in *.go (zenoh)
  └ 18 lines found

● Read sample.go
  │ zenoh/sample.go
  └ 118 lines read

● Read handler.go
  │ zenoh/handler.go
  └ 88 lines read

● Search (grep)
  │ "type .*Event struct|func \(e \*.*Event\)" in *.go (zenoh)
  └ 6 lines found

● Search (grep)
  │ "Transports\(\)|Links\(nil\)|TransportEvent|LinkEvent" in **/*.go
  └ 81 lines found

● Read query.go
  │ zenoh/query.go
  └ L1:80 (80 lines read)

I have the main findings now. I’m doing one last pass against the pre-change example and surrounding code so the report can separate true issues from intentional design shifts.

● Show base z_info example (shell)
  │ git --no-pager show origin/main:examples/z_info/z_info.go | sed -n '1,180p'
  └ 58 lines...

● Show key patch hunks (shell)
  │ git --no-pager diff origin/main...HEAD -- examples/z_info/z_info.go zenoh/link.go
  │ zenoh/transport.go tests/connectivity_test.go | sed -n '1,260p'
  └ 261 lines...

● Read common.go
  │ zenoh/common.go
  └ L110:140 (31 lines read)

● Search (grep)
  │ "type Reliability int|const \(|Reliable|BestEffort" in *.go (zenoh)
  └ 14 lines found

● report_failure (MCP: zbobr) · brief: "Review failed: listener events leak owned transport/link ob…
  └ Report stored

**Review failed.** The listener/API shape matches the approved analog well, but there are two correctness issues that should be fixed before accepting the branch:

1. **Transport/link events currently leak C-owned objects.**  
   `zenohTransportEventsCallback` and `zenohLinkEventsCallback` clone owned transports/links into each event, but `TransportEvent`/`LinkEvent` provide no matching destruction path, and the new example/tests consume them without dropping anything. That makes every connectivity event leak over time.

2. **`Link.Group()` and `Link.AuthIdentifier()` skip dropping owned strings on the empty path.**  
   Both methods return early when `z_internal_string_check(&s)` is false, but never release `s` in that branch.

The analog choice itself is good: `Transports()`/`Links()` follow the existing info-query pattern, and the listener APIs track `MatchingListener` closely. The problems are in ownership handling, not in the overall design.

--- stderr ---

Total usage est:        1 Premium request
API time spent:         1m 40s
Total session time:     1m 56s
Total code changes:     +0 -0
Breakdown by AI model:
 gpt-5.4                  497.9k in, 6.1k out, 439.6k cached (Est. 1 Premium request)
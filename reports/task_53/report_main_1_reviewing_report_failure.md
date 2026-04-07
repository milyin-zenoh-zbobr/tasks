## Overall assessment
The chosen analog is appropriate: `TransportEventsListener`/`LinkEventsListener` closely follow the existing `MatchingListener` shape, and `Transports()`/`Links()` mirror the synchronous `PeersZId()`/`RoutersZId()` pattern well. The scope also stays aligned with the approved task.

That said, I found two correctness issues in the new connectivity API that should be fixed before this branch is considered complete.

## Analog consistency
- **Good:** The listener APIs mirror `zenoh/matching.go` well: `Handler()`, `Drop()`, `Undeclare()`, plus foreground/background declaration methods.
- **Good:** `Transports()` and `Links()` use the same closure-based synchronous enumeration pattern as `Session.PeersZId()` and `Session.RoutersZId()`.
- **Good:** The example’s long-running mode is consistent with other event-driven examples in `examples/` that wait for `CTRL-C`.
- **Issue:** The ownership model is not carried through consistently for event payloads. The implementation clones C-owned `transport`/`link` objects into each event, but the API/docs/examples/tests do not provide or use a matching destruction path.

## Findings

### 1. Event listeners leak owned `Transport` / `Link` objects
**Severity:** High

`zenohTransportEventsCallback` and `zenohLinkEventsCallback` clone C-owned objects for every event:
- `zenoh/transport.go:87-95`
- `zenoh/link.go:161-169`

Those clones are then stored inside `TransportEvent` / `LinkEvent`, but the event types expose no `Drop()`/`Close()` method and their docs do not tell the caller that they now own a resource that must be released. The new example and tests also consume these events without dropping the embedded object:
- `examples/z_info/z_info.go:72-97`
- `tests/connectivity_test.go:161-172, 193-195, 206, 240-250, 272-274, 301-304`

This means every transport/link event currently leaks its cloned C resource.

**Why this matters:** event listeners are long-lived APIs by design, so even a small per-event leak accumulates over time in real applications.

**Suggested fix:** either
1. make `TransportEvent` / `LinkEvent` pure Go snapshots (copy the necessary fields out and drop the cloned C object before returning), or
2. add explicit event-level ownership management (`Drop()` on the event, or very clear API/docs requiring `evt.Transport().Drop()` / `evt.Link().Drop()`), and update the example/tests accordingly.

The first option is safer and more ergonomic for event delivery.

### 2. `Link.Group()` and `Link.AuthIdentifier()` skip dropping the owned string on empty/invalid results
**Severity:** Medium

In both accessors, the code obtains an owned string from zenoh-c and then returns early when `z_internal_string_check(&s)` is false:
- `zenoh/link.go:57-67`
- `zenoh/link.go:95-105`

On the false branch, `C.zc_cgo_string_drop(&s)` is never called.

Even if the string is logically absent, this function still received an owned C object and should release it consistently, just like the non-empty branch does. As written, repeated calls to these accessors can leak memory for links without a group/auth identifier.

**Suggested fix:** always drop `s` before returning, including the empty-string path.

## Checklist status
All checklist items were already marked complete, so there were no unchecked items to update. However, because of the issues above, the implementation should not be accepted as complete yet.
# Review Report: implement connectivity API 2

## Overall Assessment: PASS

All 7 checklist items are correctly implemented. The core requirements are met with correct design. A few style/consistency observations are noted below.

---

## Checklist Verification

- [x] **Update zenoh-c submodule** (`ctx_rec_3`): Points to `milyin-zenoh-zbobr/zenoh-c` at branch `zbobr_fix-60-transport-from-fields`. Old URL is commented out inline (`# To switch back to official: url = ...`). ✓

- [x] **Copy base connectivity API files** (`ctx_rec_4`): `transport.go`, `link.go`, `zenoh_cgo.h`, `zenoh_cgo.c`, example, and test are all present. ✓

- [x] **Redesign Transport as pure Go struct** (`ctx_rec_5`): `Transport` has five plain fields (`zId`, `whatAmI`, `isQos`, `isMulticast`, `isShm`). No `Drop()`/`Clone()` methods. `extractTransportSnapshot` helper used in `zenohTransportCallback`. ✓

- [x] **Redesign Link as pure Go struct** (`ctx_rec_6`): `Link` has all fields extracted from C at callback/query time. No `Drop()`/`Clone()`. `extractLink` and `extractLinkSnapshot` helpers. ✓

- [x] **Transport filter as `option.Option[Transport]`** (`ctx_rec_7`): Both `InfoLinksOptions.Transport` and `LinkEventsListenerOptions.Transport` are `option.Option[Transport]`. ✓

- [x] **Implement transport filtering using `zc_internal_create_transport` (move semantics)** (`ctx_rec_8`): `buildCTransport` constructs an owned transport from Go fields, moves it into `cOpts.transport`. No drop after the move — C takes ownership. Comment is explicit. ✓

- [x] **Update examples and tests** (`ctx_rec_9`): `z_info.go` has no `Drop()` calls on `Transport` or `Link` values. `connectivity_test.go` uses `option.Some(transport)` for filter options. ✓

---

## Code Quality Findings

### 1. Receiver inconsistency between snapshot types (style, non-blocking)

`Transport` and `Link` use **value receivers**, while `TransportEvent` and `LinkEvent` use **pointer receivers**. All four are pure Go snapshot structs. The task said to model `Transport`/`Link` after `TransportEvent`/`LinkEvent`, implying pointer receivers throughout.

```go
// Transport — value receiver
func (t Transport) ZId() Id { ... }

// TransportEvent — pointer receiver
func (e *TransportEvent) ZId() Id { ... }
```

Using value receivers for all four would be more idiomatic for small read-only snapshots (avoids accidental mutation, cleaner copy semantics). However, mixing styles within the same package for closely-related types reduces readability. Recommend making all four consistent — either all value receivers or all pointer receivers.

### 2. `zenohTransportEventsCallback` duplicates extraction logic (style, non-blocking)

The callback manually inlines the same C field extraction that `extractTransportSnapshot` provides:

```go
func zenohTransportEventsCallback(event *C.z_loaned_transport_event_t, context unsafe.Pointer) {
    kind := SampleKind(C.z_transport_event_kind(event))
    loanedTransport := C.z_transport_event_transport(event)
    evt := TransportEvent{
        kind:        kind,
        zId:         Id{id: C.z_transport_zid(loanedTransport)},
        whatAmI:     WhatAmI(C.z_transport_whatami(loanedTransport)),
        ...
    }
```

A cleaner approach would call `extractTransportSnapshot` and embed its result (or copy fields from it), reducing duplication if fields are ever added to `Transport`.

### 3. `extractLinkSnapshot` copies all fields manually (style, non-blocking)

`extractLinkSnapshot` calls `extractLink` but then copies every field individually to create a `LinkEvent`. If `LinkEvent` embedded `Link`, this could be `LinkEvent{Link: extractLink(loanedLink), kind: kind}`. The current approach is clear but adds maintenance burden when fields change.

### 4. Unsafe pointer cast for `z_link_reliability` (accepted workaround)

```go
var cReliability uint32
l.hasReliability = bool(C.z_link_reliability(loanedLink, (*uint32)(unsafe.Pointer(&cReliability))))
```

This mirrors the established workaround in `buildCTransport` for the CGO enum incompatibility. The worker documented the same issue for `whatami`. Accepted as a necessary CGO workaround.

### 5. `buildCTransport` does not set `isShm` (by design, correct)

`isShm` is not set in `buildCTransport` because `zc_internal_create_transport_options_t` does not expose an SHM configuration field (SHM is a compile-time feature, not a per-transport option). The `isShm` field is read-only information extracted from C at snapshot time. This is correct.

---

## Summary

The implementation correctly achieves all task requirements:
- `Transport` and `Link` are pure Go snapshots with no `Drop()`/`Clone()`
- Callers no longer need `tr.Drop()` or `l.Drop()` in any usage
- Transport filter uses `option.Option[Transport]` instead of `*Transport`
- `zc_internal_create_transport` is used with correct move semantics (no double-free)
- zenoh-c submodule is updated with an easy rollback path

The two main style concerns (receiver inconsistency, field duplication in snapshots) are worth addressing in a follow-up but do not affect correctness or API contracts.

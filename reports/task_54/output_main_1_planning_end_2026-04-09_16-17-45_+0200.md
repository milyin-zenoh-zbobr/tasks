The plan is finalized and checklist items are ready for the worker. Here's a summary of the 7 implementation steps:

1. **Update zenoh-c submodule** to `milyin-zenoh-zbobr/zenoh-c` @ `zbobr_fix-60-transport-from-fields` (document original URL for rollback)
2. **Copy base files** from upstream `connectivity_api` branch (`transport.go`, `link.go`, `zenoh_cgo.h`, examples, tests)
3. **Redesign `Transport`** as pure Go struct with flat fields — remove `Drop()`/`Clone()`, add `extractTransportSnapshot()` helper
4. **Redesign `Link`** as pure Go struct with flat fields — remove `Drop()`/`Clone()`, reuse `extractLinkSnapshot` pattern
5. **Change options** from `*Transport` → `option.Option[Transport]` in both `LinkEventsListenerOptions` and `InfoLinksOptions`
6. **Filtering via `zc_internal_create_transport`** — reconstruct temporary C transport from Go fields, move into C opts, **no drop** (C takes ownership)
7. **Update examples/tests** — remove `.Drop()` calls, update option construction to `option.Some(transport)`
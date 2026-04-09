All work is complete. Here's what was implemented:

**2 commits** on `zbobr_fix-54-implement-connectivity-api-2`:

1. **zenoh-c submodule** switched to `milyin-zenoh-zbobr/zenoh-c@zbobr_fix-60-transport-from-fields` (provides `zc_internal_create_transport`). Original URL preserved as a comment for easy rollback.

2. **Connectivity API** — all 6 implementation items:
   - `Transport`: pure Go struct (5 fields, no Drop/Clone), `extractTransportSnapshot` helper, callback updated
   - `Link`: pure Go struct (same fields as `LinkEvent` minus `kind`), `extractLink` helper, callback updated  
   - `LinkEventsListenerOptions.Transport` and `InfoLinksOptions.Transport`: `*Transport` → `option.Option[Transport]`
   - `buildCTransport()`: reconstructs a C-owned transport from Go fields via `zc_internal_create_transport`; C takes ownership via move semantics (no drop)
   - `zc_cgo_transport_is_shm` wrapper handles `Z_FEATURE_SHARED_MEMORY` conditional compilation (returns `false` when SHM not available)
   - Examples and tests: no `Drop()`/`Clone()` on Transport/Link, `option.Some(transport)` for filter options

`go build ./...` and `go vet ./...` both pass cleanly.
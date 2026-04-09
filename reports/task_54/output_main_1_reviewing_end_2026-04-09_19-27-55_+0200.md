The review is complete. All 3 checklist items for the `TransportEvent`/`LinkEvent` accessor refactor phase are correctly implemented:

- **`TransportEvent`** now wraps a single `Transport` field accessed via `Transport()` — no duplicated methods
- **`LinkEvent`** now wraps a single `Link` field accessed via `Link()` — no duplicated methods  
- All call sites in tests and examples updated to use the new accessors

One minor note flagged (not a blocker): `buildCTransport` uses an unsafe pointer cast for `cOpts.whatami` that could likely be replaced with a direct `C.z_whatami_t(...)` cast, and the function lives in `link.go` rather than `transport.go` where it logically belongs. Neither affects correctness.
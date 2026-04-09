# Plan: TransportEvent/LinkEvent refactor to wrap Transport/Link

## Design decisions
- Follow the Rust API pattern (z_info.rs): events wrap their data counterpart via a single accessor, not repeat its surface.
- `TransportEvent` replaces 5 duplicate fields/methods with `transport Transport` field + `Transport() Transport` accessor.
- `LinkEvent` replaces 10 duplicate fields/methods with `link Link` field + `Link() Link` accessor.
- `extractLinkSnapshot` simplifies: already calls `extractLink`, now just embeds the result directly.
- 3 checklist items cover: (1) TransportEvent refactor, (2) LinkEvent refactor, (3) updating all call sites in tests + examples.

## Chosen analog
The existing `Transport` and `Link` pure-Go structs (already implemented in this branch) are the wrappers; events become thin shells with `Kind()` + one accessor.

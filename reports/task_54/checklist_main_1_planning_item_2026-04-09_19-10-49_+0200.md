In `zenoh/link.go`, redesign `LinkEvent`:
- Replace all 10 duplicated fields (`zId`, `src`, `dst`, `group`, `mtu`, `isStreamed`, `interfaces`, `authIdentifier`, `priorityMin`/`priorityMax`/`hasPriorities`, `reliability`/`hasReliability`) with a single `link Link` field.
- Remove all 10 duplicated methods: `ZId()`, `Src()`, `Dst()`, `Group()`, `Mtu()`, `IsStreamed()`, `Interfaces()`, `AuthIdentifier()`, `Priorities()`, `Reliability()`.
- Add a `Link() Link` accessor method that returns `e.link`.
- Simplify `extractLinkSnapshot` to return `LinkEvent{kind: kind, link: extractLink(loanedLink)}` — it already calls `extractLink`, just embed the result directly instead of copying each field.

This mirrors the `TransportEvent` change and eliminates the field duplication.
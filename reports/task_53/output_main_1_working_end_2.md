All review issues have been fixed across 4 commits:

1. **String leak fix** — `Link.Group()` and `Link.AuthIdentifier()` now always drop the owned C string via `defer`, including on the empty-result path.

2. **Event memory leak fix** — `TransportEvent` and `LinkEvent` are now pure Go snapshots (like `MatchingStatus`). The callbacks extract all fields from loaned C pointers without cloning, so no C resources need management. Direct accessors (`evt.ZId()`, `evt.Src()`, etc.) replace the old `evt.Transport().X()` / `evt.Link().X()` pattern.

3. **Tests and example updated** to use the new snapshot API.
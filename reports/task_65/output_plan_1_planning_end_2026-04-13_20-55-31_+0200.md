The plan is ready. Here's a summary of what it covers:

## Plan: Full Connectivity API for zenoh-kotlin

**What was wrong with previous attempts:**
- Only covered transport events, missing links, link events, background listeners, and transport filter
- Flattened `Transport`/`Link` fields instead of using proper snapshot types
- Missing upstream fields (`isShm`, `authIdentifier`, `priorities`, `reliability`)
- No story for passing `Transport` back to JNI for link filtering

**This plan addresses all rejection reasons:**

### Full API surface (6 entry points on `SessionInfo`):
1. `transports()` → snapshot list
2. `declareTransportEventsListener(...)` → 3 overloads (callback/handler/channel)
3. `declareBackgroundTransportEventsListener(...)` → callback-only, returns `Unit`
4. `links(transport?)` → snapshot list with optional transport filter
5. `declareLinkEventsListener(...)` → 3 overloads + optional transport filter
6. `declareBackgroundLinkEventsListener(...)` → callback-only + optional transport filter

### Key design decisions:
- **Transport filter**: Kotlin `Transport` stores all fields; when passed as filter, fields are sent flat to JNI where Rust reconstructs via `Transport::new_from_fields()` (accessible via `internal` feature already enabled in `Cargo.toml`)
- **Background listeners**: Use Rust's `.background()` builder which sets `undeclare_on_drop = false`; return `Unit` (no pointer to manage)
- **`isShm`**: Always exposed as `Boolean` in Kotlin; Rust uses `#[cfg(feature = "shared-memory")]` to set it
- **Lifecycle**: Both listener types follow `MatchingListener` pattern (`SessionDeclaration` + `isValid()` + `undeclare()` + `finalize()`); added to `strongDeclarations` in `Session.kt`
- **Delegation chain**: `SessionInfo` → `Session` (internal) → `JNISession` → JNI, matching existing `zid`/`peersZid`/`routersZid` pattern
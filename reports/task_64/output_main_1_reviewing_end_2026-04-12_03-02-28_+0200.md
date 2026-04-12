Review complete. The implementation is correct and all checklist items are done. Here's a summary of the findings:

**Verified:**
- `RepoResponse` extended with `fork: bool` and `parent: Option<ParentRepo>` — consistent with the existing `#[allow(dead_code)]` attribute pattern
- `sync_fork_if_needed` follows the same GET pattern as `validate_connectivity` (retry_github + octocrab.get::<RepoResponse, _, _>); non-fatal error handling for 403/409/422 is correct
- Call is placed in `ensure_bare_clone_github` just before `fetch origin`, matching the plan exactly

**Minor observations (non-blocking):**
1. `ParentRepo` struct and `parent` field are deserialized but never used in logic — harmless, the merge-upstream endpoint correctly uses `repo.owner()`/`repo.name()` from the existing `GitHubRepo` struct
2. The merge-upstream POST is not wrapped in `retry_github` — this is a pragmatic trade-off since custom non-fatal error handling needs the raw `octocrab::Error`
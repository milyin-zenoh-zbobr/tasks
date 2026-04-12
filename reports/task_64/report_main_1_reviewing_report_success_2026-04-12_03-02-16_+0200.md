# Review Report: Fork Sync Before Fetch

## Summary

All checklist items are implemented and the change is correct. Single file modified: `zbobr-repo-backend-github/src/github.rs`.

## Analog Consistency

The chosen analog is `validate_connectivity` (line 958), which also calls `GET /repos/{repo_path}` via `retry_github` + `octocrab.get::<RepoResponse, _, _>`. The `sync_fork_if_needed` GET call follows this pattern exactly — consistent authorship. The POST error-handling uses the same `matches!` pattern style as `is_transient_octocrab_error`.

## Checklist Items

- ✅ **RepoResponse extended**: Added `fork: bool` and `parent: Option<ParentRepo>` to `RepoResponse`; added `ParentRepo` struct with `full_name: String`. Both carry `#[allow(dead_code)]` consistent with the existing struct.
- ✅ **`sync_fork_if_needed` implemented**: GET checks fork status via `retry_github`; POST calls `merge-upstream` API; 403/409/422 are non-fatal (warn + continue); other errors propagate.
- ✅ **Called from `ensure_bare_clone_github`**: Inserted just before `git_env fetch origin`, so the subsequent fetch picks up synced content from GitHub. Non-fork repos hit `return Ok(())` early after one API call.

## Minor Observations (non-blocking)

1. **`parent` field is unused in logic**: `RepoResponse::parent` and `ParentRepo` are deserialized but never read. The merge-upstream endpoint is correctly constructed from `repo.owner()`/`repo.name()` (the fork's own coordinates), not `parent.full_name`. The `#[allow(dead_code)]` suppresses the compiler warning. This is harmless and consistent with the plan specification.

2. **POST not wrapped in `retry_github`**: The `merge-upstream` POST does not use `retry_github`, so transient 5xx errors won't be retried. This is a deliberate trade-off: the custom non-fatal handling (403/409/422 → warn) requires access to the raw `octocrab::Error`, which `retry_github` would convert to `anyhow::Error`. The design is pragmatic and correct.

3. **API call on every invocation**: `ensure_bare_clone_github` is called on every `update_worktree` and `fetch_refs`. For non-fork repos this adds one extra GET per operation. Acceptable given the plan intent ("sync before fetching").

## Verdict

Implementation is correct, follows existing patterns and coding style, and all checklist items are complete.

Plan is ready and approved. Here's a summary:

## Plan: Auto-sync fork (`auto_sync_fork: bool`)

**Two changes:**

1. **`zbobr-repo-backend-github/src/config.rs`** — Add `auto_sync_fork: bool` (default `true`) to `ZbobrRepoBackendGithubConfig`, following the same pattern as `overwrite_author` in the dispatcher config.

2. **`zbobr-repo-backend-github/src/github.rs`** — Add `maybe_sync_fork` method that:
   - Short-circuits if `auto_sync_fork = false`
   - Checks via `GET /repos/{owner}/{repo}` if the repo is a fork
   - If yes, calls `POST /repos/{owner}/{repo}/merge-upstream` with the base branch using the existing `retry_github` pattern
   - Logs the `merge_type` result
   
   Called in `ensure_bare_clone_github` just before `git fetch origin`, covering all fetch paths automatically.
# Fork Sync Implementation — Complete

## What was done

Single file changed: `zbobr-repo-backend-github/src/github.rs`

### 1. Extended `RepoResponse` struct
Added `fork: bool` and `parent: Option<ParentRepo>` to capture GitHub's fork metadata. Added new `ParentRepo` struct with `full_name: String`.

### 2. Added `sync_fork_if_needed` method on `ZbobrRepoBackendGithub`
- Calls `GET /repos/{full_name}` via `retry_github` to check if the repo is a fork
- If `fork == false`, returns immediately (no-op for non-fork repos)
- If `fork == true`, calls `POST /repos/{owner}/{repo}/merge-upstream` with `{"branch": <configured-branch>}` — GitHub's native fork sync endpoint
- Non-fatal error handling: HTTP 403/409/422 responses → `tracing::warn!` and continue; other errors are propagated

### 3. Inserted call in `ensure_bare_clone_github`
`self.sync_fork_if_needed(repo).await?` is called just before the existing `git_env fetch origin`, so the subsequent fetch picks up the freshly synced upstream content.

## Verification
- `cargo build -p zbobr-repo-backend-github` — clean build
- `cargo test -p zbobr-repo-backend-github` — 31/31 tests pass
- Commit: d7ea4bf2

# Plan: If Destination Repo Is Fork, Sync It

## Problem

When the zbobr destination repo is a GitHub fork, its base branch may lag behind the upstream parent. Zbobr should sync the fork before creating worktrees, so agents work on up-to-date content.

## Approach

Single file change: `zbobr-repo-backend-github/src/github.rs`

### 1. Extend `RepoResponse` (line 84)

Add `fork: bool` to capture GitHub's fork flag from the `GET /repos/{owner}/{repo}` response.

### 2. Add `sync_fork_if_needed(&self, repo: &GitHubRepo)`

- Calls `GET /repos/{full_name}` using the existing `retry_github` + `self.octocrab.get` pattern (same as `validate_connectivity` at line 884)
- If `fork == true`: calls `POST /repos/{owner}/{repo}/merge-upstream` with `{"branch": self.backend_config.branch}` — this is GitHub's native fork sync endpoint
- Non-fatal error handling: 409 (conflict), 422 (unprocessable), 403 (no push permissions) → log `tracing::warn!` and continue; do not fail the pipeline

### 3. Call `sync_fork_if_needed` from `ensure_bare_clone_github` (line 299)

Insert the call just before the existing `git_env fetch origin` at line 341. The fetch that already follows will pick up the freshly synced fork branch from GitHub — no extra fetch step needed.

## Why this location

`ensure_bare_clone_github` is the canonical setup point for the bare repo, already ending with a fetch. Inserting the API fork sync before that fetch means both `update_worktree` and `fetch_refs` benefit automatically.

## Verification

1. Configure zbobr with a forked GitHub repo as destination
2. Commit to upstream parent; confirm fork is behind
3. Run zbobr — verify fork base branch is synced before worktree setup
4. Non-fork repos: `fork == false` path skips the API call entirely
5. `cargo test -p zbobr-repo-backend-github`

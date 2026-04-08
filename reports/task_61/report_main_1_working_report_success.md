# Implementation: auto_sync_fork

## Changes

### `zbobr-repo-backend-github/src/config.rs`
- Added `auto_sync_fork: bool` field to `ZbobrRepoBackendGithubConfig` with `#[arg(long)]` annotation
- Default value: `true` (existing users get automatic fork sync without config changes)

### `zbobr-repo-backend-github/src/github.rs`
- Extended `RepoResponse` with `fork: bool` field to detect fork status from GET /repos/{owner}/{repo}
- Added `MergeUpstreamResponse` struct (with `merge_type: String`) for the merge-upstream API response
- Added private `maybe_sync_fork(&self, repo: &GitHubRepo, branch: &str)` method in `impl ZbobrRepoBackendGithub`:
  - Short-circuits if `auto_sync_fork == false`
  - Calls GET /repos/{owner}/{repo} to check fork status
  - If fork, calls POST /repos/{owner}/{repo}/merge-upstream using existing `retry_github` pattern
  - Logs `merge_type` (none/fast-forward/merge) at info level; logs warning on failure (non-fatal)
- Called `maybe_sync_fork` in `ensure_bare_clone_github` right before `git fetch origin`
- Fixed two inline test struct literals to include `auto_sync_fork: true`

## Test results
All 31 tests pass (cargo test -p zbobr-repo-backend-github).

## Commit
a4e6df32 feat: add auto_sync_fork config option to sync forks before fetching
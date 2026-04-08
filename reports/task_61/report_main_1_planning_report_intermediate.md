## Proposed Plan: Auto-sync fork before fetching

### What changes

**`zbobr-repo-backend-github/src/config.rs`**
- Add `auto_sync_fork: bool` field to `ZbobrRepoBackendGithubConfig`, default `true`, exposed via `#[arg(long)]`

**`zbobr-repo-backend-github/src/github.rs`**
- Add private method `maybe_sync_fork(&self, repo: &GitHubRepo, branch: &str)`:
  - Skips immediately if `auto_sync_fork = false`
  - Calls `GET /repos/{owner}/{repo}` to check if it's a fork
  - If fork, calls `POST /repos/{owner}/{repo}/merge-upstream` with `{"branch": branch}` using existing `retry_github` pattern
  - Logs the result (`merge_type`: none / fast-forward / merge)
- Update `ensure_bare_clone_github` to accept `base_branch: &str` and call `maybe_sync_fork` right before `git fetch origin`

### Why this approach

- Syncing via GitHub API (merge-upstream) is the correct way to bring a fork's base branch up to date with upstream — it's atomic and doesn't require local git manipulation
- Placing the sync inside `ensure_bare_clone_github` covers both `update_worktree` and `fetch_refs` call sites automatically
- Defaulting to `true` means forks are synced automatically without any user config change, matching the issue's intent
In `zbobr-repo-backend-github/src/github.rs`, implement fork auto-sync logic:

**New private method `maybe_sync_fork(&self, owner: &str, repo: &str, branch: &str)`:**
- If `self.backend_config.auto_sync_fork == false`, return immediately (no-op)
- Use octocrab to call `GET /repos/{owner}/{repo}` and inspect the `fork` field on the response
- If `fork == true`, call `POST /repos/{owner}/{repo}/merge-upstream` with body `{"branch": branch}` using the existing `retry_github` pattern already used in the file
- Log the `merge_type` value from the response (`none`, `fast-forward`, or `merge`) at info level
- If the repo is not a fork, skip silently

**Integration point:**
- In `ensure_bare_clone_github`, call `maybe_sync_fork(owner, repo, base_branch)` right before the `git fetch origin` command
- This ensures both `update_worktree` and `fetch_refs` benefit automatically without duplicating the call

Why: GitHub's merge-upstream API is the canonical way to bring a fork's branch in sync with upstream — atomic, no local git manipulation needed. Placing it in `ensure_bare_clone_github` is the single correct choke point that covers all fetch paths.
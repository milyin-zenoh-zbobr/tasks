**Plan v20** resolves both blocking issues from v19:

**Issue 1 — `check_is_git_repo` ambiguity:**
The new `check_worktree_presence(dir) -> Result<bool>` function captures stderr from `git rev-parse --is-inside-work-tree` and specifically checks for the `"not a git repository"` string. This gives a true three-way distinction:
- `Ok(true)` — confirmed git repo
- `Ok(false)` — expected first-run no-repo case
- `Err(...)` — unexpected git failure (corrupt repo, permissions, etc.)

`git_check` is not used because it collapses all non-zero exits to `Ok(false)`.

**Issue 2 — Commit metadata lost when push fails:**
`perform_stash_and_push` retains its `-> anyhow::Result<()>` return type and stores commits internally. Before the first `update_worktree` call (which can fail on merge conflicts), pre-rewrite commits are collected and stored immediately (non-fatal). After rewrite (if configured), post-rewrite SHAs overwrite the stored pre-rewrite ones. Even if the merge/push fails, commits are already in the task record.

The rewrite must remain after the first `update_worktree` (not before it) because rewriting local SHAs before a remote merge would cause SHA conflicts when pushing — this constraint forced the "store early, overwrite after rewrite" design.

All other v19 decisions (per-path finalization semantics, retry-path handling, markdown serialization, reviewer prompt) are preserved unchanged.
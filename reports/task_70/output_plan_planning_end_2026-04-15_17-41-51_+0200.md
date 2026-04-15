The plan is ready. Here's a summary of what it proposes:

## Plan v12: Show Commits in Context

**Core fix for the rewriting problem:** Change the `git filter-branch` range in `rewrite_authors_on_worktree` from `dest_branch..HEAD` to `commit_baseline..HEAD`. Since `commit_baseline` is the *boundary* of the rewrite range, it is never itself rewritten — making `git log commit_baseline..HEAD` stable before and after author rewriting.

**New user requirement addressed:** `rewrite_authors_on_worktree` will only touch current-stage commits (agent + finalization merge commits), not the entire branch history. User commits arrive as second parents of merge commits and are excluded via `--first-parent`.

**Algorithm (per user's requirement):**
1. Capture `commit_baseline = git rev-parse HEAD` at stage iteration start
2. Pass `commit_baseline` through `finalize_stage_session` → `perform_stash_and_push` → `rewrite_authors_on_worktree`
3. After `finalize_stage_session` returns, capture `git log --first-parent commit_baseline..HEAD` and store in `StageContext.commits`

**Files changed:** `zbobr-api/src/task.rs`, `zbobr-api/src/context/mod.rs`, `zbobr-utility/src/lib.rs`, `zbobr-dispatcher/src/cli.rs`, `zbobr/src/init.rs`
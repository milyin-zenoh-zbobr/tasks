The plan v23 is ready. Here's a summary of the two key fixes over v22:

**Fix 1 — Post-rewrite collection without `pre_update_head`:**
After `filter-branch`, `pre_update_head` is stale (it was one of the rewritten stage commits). Instead, use `commit_baseline` (the exclusive lower bound, never rewritten) to collect all commits after rewrite, then apply a count-based skip: `ff_count = total - N - M` (where N = pre-sync agent count, M = sync merge count captured before the rewrite). This correctly skips fast-forwarded remote commits in case A, and keeps everything in case B (merge sync).

**Fix 2 — Abbreviated SHAs everywhere:**
Store 12-char abbreviated SHAs in `StageContext.commits`, render identically in both persist-mode (user-visible) and prompt-mode. Update `rewrite_authors_on_worktree`'s env-filter to use shell prefix matching (`case "$GIT_COMMIT" in "${prefix}"*`) so it works with the abbreviated stored SHAs.
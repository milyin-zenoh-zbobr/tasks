Plan v15 submitted. The two targeted fixes over Plan v14:

1. **Retry-path rewrite is now fatal**: Changed `if let Err(e) = rewrite_authors_on_worktree(...) { warn }` to `rewrite_authors_on_worktree(...).await?`. If `overwrite_author=true` and the retry-path rewrite fails, the stage fails rather than silently continuing with incorrect author metadata — consistent with how `perform_stash_and_push` already handles rewrite failures on the final path.

2. **Reviewer prompt references the full context**: The `REVIEWER_PROMPT` guidance for commit classification now says "commits listed in ANY `Commits:` field anywhere in the task context (across all stages and retry attempts)" rather than per-stage. This prevents the reviewer from misclassifying agent commits from earlier attempts as user-introduced just because they aren't in the current stage's list.

Everything else from Plan v14 (per-attempt baseline inside the retry loop, `--first-parent` traversal, markdown serialization, `lower_bound` rename, capture-after-finalization for final path) remains unchanged.
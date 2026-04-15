Plan v20 is not implementation-ready yet. It fixes the two issues from v19, but two new design gaps remain.

1. **Finalization still drops commits created by the first successful sync when `overwrite_author` does not run.**
   - In this codebase, `perform_stash_and_push` calls `update_worktree`, and `update_worktree` can create merge commits before the final push (`zbobr-repo-backend-github/src/github.rs:860-878`: merge remote work branch, merge base branch, then push).
   - The plan stores `pre_commits` *before* the first `update_worktree`, then only overwrites the stored list after a rewrite. That means when `overwrite_author == false`, or when rewrite is skipped for any other reason, the stage record never gets the post-sync merge commits produced during finalization.
   - That breaks the core feature: later reviewers are supposed to treat hashes listed in `Commits:` as the known agent/system commits for the stage. Under this plan, some system-generated finalization commits would be absent and therefore look like user commits.
   - **Required fix:** keep the early pre-sync store for failure resilience, but after any successful first `update_worktree` collect the post-sync commit set and overwrite the stage record with that final set even when no author rewrite happens. If rewrite then runs, collect once more after rewrite and overwrite again with the rewritten hashes.

2. **`overwrite_author` still uses branch-wide redetection instead of the recorded stage commit set.**
   - The command already loads the full task snapshot (`zbobr/src/commands.rs:615-619`), so it has direct access to `task.context.stages`.
   - But the plan says to compute `agent_commits` with `collect_agent_commits(&repo_dir, dest_branch)`. That is a fresh heuristic over the current branch, not the exact commit ownership data recorded per stage.
   - This violates the new requirement from the task discussion: author rewriting must depend on the mechanism that determines stage-owned commits, and it must avoid rewriting commits made by other authors. A branch-wide `dest_branch..HEAD` scan can still include human commits made directly on the work branch, so it is not safe enough.
   - **Required fix:** make `overwrite_author` use the exact union of hashes already recorded in `StageContext.commits` (across stages / retry attempts as needed), and pass that set to `rewrite_authors_on_worktree`. If the task has no recorded commits yet, the command should report that there is nothing safely rewriteable rather than recomputing a broader set from the branch.

With those two changes, the rest of v20 looks directionally consistent with the existing code and close to ready.
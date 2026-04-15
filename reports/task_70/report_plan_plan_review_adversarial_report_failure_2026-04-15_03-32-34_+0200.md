The plan’s overall direction is good: adding `StageContext.commits`, parsing/rendering a `Commits:` line in `zbobr-api/src/context/mod.rs`, preserving commits-only stages in prompt mode, and updating the reviewer prompt all fit the current code structure.

However, I do **not** think the plan is implementation-ready yet because its commit-capture point is still too early for the actual stage lifecycle.

## Blocking issue: the plan captures commits before finalization, but finalization itself can create more commits

The plan intentionally moves commit collection to immediately after `execute_tool()` returns, before any retry `continue`, to avoid losing commits from failed attempts. That fixes the earlier retry problem, but it introduces a new under-capture problem for the final attempt.

In the current code, a stage is not really finished when `execute_tool()` returns:

- `zbobr-dispatcher/src/cli.rs:681-691` calls `finalize_stage_session(...)`
- `finalize_stage_session()` calls `perform_stash_and_push(...)` in all completion paths (`cli.rs:2006-2061`)
- `perform_stash_and_push()` calls `update_worktree(...)` (`cli.rs:2161-2189`)
- In the GitHub repo backend, `update_worktree()` can perform real merges and then push (`zbobr-repo-backend-github/src/github.rs:857-880`)
  - merge remote work -> local work (`lines 860-868`)
  - merge base -> local work (`lines 870-875`)
  - push result (`lines 877-878`)

Those merges can create new merge commits **after** the plan’s proposed `collect_agent_commits(... baseline .. HEAD)` runs.

## Why this breaks the intended attribution

Issue #314 wants the context to distinguish agent commits from user commits. Under the proposed plan:

1. the agent makes commit(s)
2. the dispatcher records `baseline..HEAD` immediately after `execute_tool()`
3. finalization merges remote/base and creates additional commit(s)
4. those new commits are absent from `StageContext.commits`

Later, the reviewer prompt says commits listed under `Commits:` are agent commits and commits not listed there are likely user commits. That would be false for these finalization-created merge commits: they were created by zbobr during the stage, not by the user.

This is not theoretical; the current GitHub backend explicitly performs merge operations during `update_worktree()`.

## What the plan needs to specify instead

The revised plan should define commit attribution across **both** parts of the stage lifecycle:

1. **Attempt-local capture before retry branching**
   - keep the per-attempt baseline before `execute_tool()`
   - keep the immediate post-`execute_tool()` capture so failed attempts that hit `continue` are not lost

2. **Final-attempt post-finalization reconciliation**
   - after `finalize_stage_session()` returns for the non-retried attempt, collect any additional commits created since the immediate post-execution capture and append them to that same stage’s `commits`
   - this must cover backend-generated merge commits and any other finalization-time commits

Equivalent designs are fine, but the plan must explicitly cover both retry preservation **and** finalization-generated commits. Until it does, the `Commits:` field will systematically under-report agent/system commits on GitHub-backed tasks and mislead the reviewer prompt.

## Recommendation

Keep the model / markdown / prompt parts of the plan. Revise only the commit-capture lifecycle so it spans the whole stage, not just the executor run. After that, the plan should be implementation-ready.
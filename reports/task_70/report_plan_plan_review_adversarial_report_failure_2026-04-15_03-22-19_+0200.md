The plan’s **context-model and markdown direction is good**: adding `StageContext.commits`, parsing the `Commits:` line in `MdContext::from_str`, keeping commits-only stages in prompt mode, and updating the reviewer prompt all match the current code structure.

However, I do **not** think the plan is implementation-ready yet because its retry/commit-attribution model is still unsound.

## Blocking issue: retried failed attempts can still produce commits, but the plan records commits only in finalization

The plan says that when `outcome.execution_failed && attempts_remaining > 0`, the loop continues and the discarded attempt can safely keep `commits = []` because these are only provider-level failures where the agent did not run and no commits were made.

That is not true in the current implementation.

### What the code does today

In `zbobr-dispatcher/src/cli.rs`, `execute_tool()` returns:
- `execution_failed = false` only for `exit_ok: true`
- `execution_failed = true` both when:
  - the executor returns `exit_ok: false`, i.e. the tool **ran** and exited non-zero, and
  - the executor returns `Err(...)`

So a failed attempt is not just “provider could not start”; it can be a real agent run that executed, changed files, and possibly created commits before exiting non-zero.

Then, in the provider retry loop:
- a new `StageContext` is pushed **for each attempt**
- if `execution_failed` and more providers remain, the code `continue`s immediately
- `finalize_stage_session()` is only called for the last attempt in the cycle

That means the plan’s proposed commit recording point — inside `finalize_stage_session()` — has no way to persist commits made by earlier failed attempts that are retried.

### Why this matters

With the plan as written:
- failed attempt A can create commits
- the dispatcher retries with provider B
- attempt A’s `StageContext` remains in context with empty `commits`
- attempt B captures a fresh baseline after A’s commits already exist, so A’s commits are no longer attributable to A

This directly conflicts with the plan’s stated **per-attempt semantics** and would make the new context misleading exactly in the cases where provider retries happen.

## What the revised plan needs to specify

The plan should explicitly choose one of these approaches:

1. **True per-attempt attribution**
   - capture a baseline before each attempt
   - after each attempt returns, collect that attempt’s commit range immediately and attach it to the just-created `StageContext` **before any `continue` retry path**
   - then let `finalize_stage_session()` handle stash/push/state transitions separately for the final attempt only

2. **Single logical-stage aggregation across retries**
   - stop pretending each retry entry is an independently attributed stage
   - define one aggregated commit list for the whole stage and store/render it accordingly

Given the current persisted model already creates one `StageContext` per attempt, option 1 is the more consistent fit.

## Recommendation

Keep the current model/markdown/prompt parts of the plan. Revise only the commit-capture lifecycle so it does not depend solely on `finalize_stage_session()`. Until that is fixed, the plan is still not ready for implementation.
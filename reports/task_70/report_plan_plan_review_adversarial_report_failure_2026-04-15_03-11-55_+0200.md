The plan’s **model/markdown direction is sound**: adding `StageContext.commits`, parsing in `MdContext::from_str`, preserving commits-only stages in prompt rendering, and clarifying the reviewer prompt all fit the current code layout. I verified the key assumptions:

- `StageContext` currently has only `info` and `records` (`zbobr-api/src/task.rs:176-186`), so the new field belongs there.
- The real parse path is `MdContext::from_str`, not `MdStage::from_str` (`zbobr-api/src/context/mod.rs:547-622`), and unrecognized lines currently fail at `bail!(...)` (`zbobr-api/src/context/mod.rs:610`).
- Prompt-mode stage filtering currently drops stages with no records (`zbobr-api/src/context/mod.rs:648-655`), so the proposed inclusion fix is needed.
- `StageContext` entries are created inside the provider retry loop (`zbobr-dispatcher/src/cli.rs:523-561`), and `finalize_stage_session()` is only called after the loop stops retrying (`zbobr-dispatcher/src/cli.rs:681-691`, `1994-2112`).

I still do **not** think the plan is implementation-ready.

## Blocking issue 1: the proposed baseline is only stage-local on the GitHub backend

The plan’s core attribution rule is to capture `git log --format=%h origin/<work_branch>..HEAD` before `perform_stash_and_push()`, with fallback to `origin/<base_branch>..HEAD`.

That matches the **GitHub backend**: its `update_worktree()` merges remote/base and then pushes the result back to origin (`zbobr-repo-backend-github/src/github.rs:860-880`), so `origin/<work_branch>` is maintained as a stage-to-stage baseline.

It does **not** match the **FS backend**. The FS backend’s `update_worktree()` only ensures the worktree and checks ancestry against the base branch; it does not push or otherwise keep `origin/<work_branch>` synchronized (`zbobr-repo-backend-fs/src/fs.rs:143-190`). On that backend, the fallback to `origin/<base_branch>..HEAD` becomes cumulative branch history, not “commits made during this stage.” On later stages it will re-report earlier-stage commits under the current stage.

That is a real architectural mismatch, not a detail for the worker to improvise around: this feature is being implemented in dispatcher/common context code, so the plan needs a baseline strategy that is valid across supported backends.

**What to change:** use a true **local stage baseline** rather than remote branch state. Capture the local `HEAD` (or equivalent empty baseline) when the stage/attempt starts, and derive the commit range from that local baseline to pre-push `HEAD`. That keeps GitHub-side user merges out of the range while also remaining correct on the FS backend.

## Blocking issue 2: the plan still does not line up cleanly with the existing per-attempt `StageContext` model

A new `StageContext` is pushed for **each provider attempt** inside the retry loop (`zbobr-dispatcher/src/cli.rs:532-560`). The plan’s recording helper, however, writes commits to `task.context.stages.last_mut()` during finalization. In practice, that means if an earlier failed provider attempt created commits, those commits will be attached to the **last** attempt’s stage entry instead of the attempt that produced them.

This is better than losing the commits entirely, but it is still semantically inconsistent with the current persisted model, where each retry already has its own stage record. Since the issue asks to append hashes in “the stage record in the context,” the plan needs to be explicit about whether retries are:

1. one logical stage with one aggregated commit list, or
2. distinct context entries that should each show only their own commits.

As written, the plan assumes (1) operationally while still storing data as (2). That ambiguity is enough to send an implementer down the wrong path.

**What to change:** either define retries as a single aggregated logical stage and store the commit list accordingly, or keep per-attempt baselines so each `StageContext` gets its own range.

## Non-blocking observations

- The plan correctly notes that `overwrite_author` rewrites SHAs later (`zbobr-dispatcher/src/cli.rs:2173-2183`, `zbobr-utility/src/lib.rs:321-351`). Since the default is `false` (`zbobr-api/src/config/mod.rs:752-769`), I would treat that as a limitation to document rather than the primary blocker.
- The implementation surface is a bit wider than listed: adding a field to `StageContext` will touch more constructors/tests than just the dispatcher insertion site.

## Recommendation

Revise the plan once more before implementation:

1. Replace the remote-branch-based baseline with a **local stage baseline** that works on both GitHub and FS backends.
2. Decide explicitly how commit attribution should behave across **provider retries**, and align the storage shape with that choice.
3. Keep the current `StageContext.commits` + markdown/parser/prompt update direction; that part is solid.

Once those two architectural points are resolved, the plan should be ready to implement.
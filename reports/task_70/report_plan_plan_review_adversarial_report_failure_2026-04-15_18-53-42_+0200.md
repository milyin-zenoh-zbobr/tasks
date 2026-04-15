I reviewed Plan v17 against the current code in `zbobr-dispatcher/src/cli.rs`, `zbobr-utility/src/lib.rs`, `zbobr-api/src/context/mod.rs`, `zbobr-api/src/task.rs`, `zbobr-task-backend-github/src/separator.rs`, `zbobr/src/commands.rs`, `zbobr/src/init.rs`, and `zbobr-repo-backend-github/src/github.rs`, plus issue #314 and prior review notes.

The plan is materially better than v16: it correctly keeps canonical SHAs in persisted markdown, re-collects after rewrite, and aligns the standalone `overwrite-author` command with first-parent-based commit detection. Those are the right core moves.

However, I do **not** consider v17 implementation-ready yet. Two blocking gaps remain.

## Blocking issue 1: v17 still does not concretely record commits for **all** `finalize_stage_session` outcomes

The current dispatcher code calls `perform_stash_and_push()` on all three finalization paths:
- interruption (`zbobr-dispatcher/src/cli.rs:2006-2015`)
- execution error (`zbobr-dispatcher/src/cli.rs:2018-2039`)
- success (`zbobr-dispatcher/src/cli.rs:2041-2061`)

That means commits can be created, merged, pushed, and even author-rewritten on **non-success** endings too.

Plan v17’s narrative says the finalization path should re-collect after `perform_stash_and_push`, but its concrete wiring section only specifies post-finalization storage in the success case:
- “After `finalize_stage_session` returns `Ok(None)` on the success path ... collect/store `post_commits`”.

That is the same structural hole previously identified in v11/v16, just restated differently. If the worker follows the concrete implementation section, interruption/error attempts will still finish without `stage.commits`, even though `perform_stash_and_push()` ran and may have produced relevant commits. Those missing hashes then cause later review/prompt logic to misclassify agent commits as user commits.

### Required revision
The plan must explicitly require the caller to:
1. call `finalize_stage_session(...)` and bind its result,
2. **unconditionally** collect/store post-finalization commits for the current attempt,
3. only then branch on `Option<anyhow::Error>` / return.

In other words, the v11 “capture commits for all finalization outcomes” requirement still needs to be spelled out as the actual control-flow change in `CliStageRunner::run`, not left implicit.

## Blocking issue 2: the commit-detection pipeline is still specified as best-effort in correctness-critical spots

V17 correctly changes `collect_agent_commits` itself to return `Result<Vec<String>>`, but it still leaves adjacent steps as warn-and-empty fallbacks:

1. **Baseline capture**
   - Plan v17 proposes:
     ```rust
     let attempt_baseline = zbobr_utility::capture_git_head(&work_dir)
         .await
         .unwrap_or_else(|e| { tracing::warn!(...); String::new() });
     ```
   - If this fails on a real git worktree, the entire attempt silently loses authoritative commit detection and, when `overwrite_author` is enabled, silently suppresses targeted rewriting too.

2. **Post-finalization storage on success path**
   - Plan v17 proposes:
     ```rust
     let post_commits = zbobr_utility::collect_agent_commits(...)
         .await
         .unwrap_or_else(|e| { tracing::warn!(...); Vec::new() });
     ```
   - That means a stage can complete successfully but still write an empty `Commits:` set for purely incidental command failure, even though this field is exactly what downstream review logic uses to distinguish agent commits from user commits.

This is the same correctness boundary as the v16 blocking issue about `collect_agent_commits`: once commit detection drives both rewrite targeting and persisted stage metadata, silent degradation is no longer acceptable in the authoritative execution path.

The current codebase shape supports that conclusion:
- persisted context is round-tripped through markdown (`zbobr-task-backend-github/src/separator.rs:97,141`), so recorded commit identity becomes shared state, not a debug hint;
- reviewer prompts are built from prompt-mode context serialization (`zbobr-dispatcher/src/prompts.rs:295`), so missing commit data directly changes later agent behavior.

### Required revision
The plan should define a stricter rule:
- If the task/attempt is operating on a git worktree, **baseline capture and authoritative final commit collection must be fatal on failure**.
- Graceful empty results are only acceptable when there is genuinely no git repo / no identity / no baseline to compare against, not when git commands fail unexpectedly on a tracked worktree.

That preserves the feature’s contract instead of silently dropping commit ownership information.

## Non-blocking observation

There is one remaining product-level mismatch worth noting but not blocking by itself:
- issue #314 asked for short hashes in context,
- v17 keeps full SHAs in persisted markdown and abbreviates only in prompt rendering.

Given the GitHub-backed round-trip model in `separator.rs`, keeping persisted storage lossless is the right architectural choice. But if short hashes are still important for the user-visible task body, the plan should eventually describe a separate human-friendly rendering strategy rather than relying on the persisted markdown line alone.

## Conclusion

Plan v17 has the right direction, but it still leaves the worker with two wrong implementation choices:
1. success-only concrete storage after finalization, despite current code having three finalization outcomes that can all produce commits;
2. warn-and-empty handling for baseline/final authoritative detection, which still allows silent loss of commit ownership data.

Those need to be revised before implementation.
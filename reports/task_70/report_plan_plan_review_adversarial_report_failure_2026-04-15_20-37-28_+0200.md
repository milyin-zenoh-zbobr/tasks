Plan v23 is **not implementation-ready yet**. It improves on v22, but after checking the actual code paths there are still two blocking design issues.

1. **The plan does not update the parser path that actually reads persisted context, so `Commits:` lines would break context parsing unless the worker infers extra work not stated in the plan.**
   - The issue requires storing short commit hashes in the persisted stage context, so the markdown parser must round-trip them.
   - In this codebase, persisted task context is parsed through `parse_context(...)` → `MdContext::from_str(...)` (`zbobr-api/src/context/mod.rs:547-621`, `714-716`), and the GitHub backend relies on that parser when reading/writing the task description (`zbobr-task-backend-github/src/separator.rs:96-98`, `141-145`).
   - But `MdContext::from_str(...)` currently only understands:
     1. `<!-- stage -->`
     2. record lines parsed by `MdRecord::try_parse(...)`
     3. stage title lines starting with `- `
     Any other non-empty line causes `bail!("Unrecognized line in context: ...")` (`zbobr-api/src/context/mod.rs:568-610`).
   - V23 says "from_str parsing: detect `Commits:` lines" and discusses `MdStage::from_str`, but `MdStage::from_str` is **not** the active entry point used when parsing the full persisted context document. The important parser is the line-by-line `MdContext::from_str(...)` state machine.
   - So as written, the plan leaves room for an implementation that updates `MdStage` rendering/parsing but forgets to teach `MdContext::from_str(...)` to accept and attach `Commits:` lines to the current stage. That would make persisted context unreadable by the existing backend.
   - **Required fix:** explicitly include changes to the `MdContext::from_str(...)` state machine so it recognizes `Commits:` lines while a stage is open and stores them on that stage, instead of bailing on them as unrecognized input.

2. **The final stored commit set is still incomplete after author rewrite because v23 stores it *before* the second `update_worktree`, even though that second sync can create a new stage-owned merge commit.**
   - The current dispatcher flow is: first `update_worktree` → optional `rewrite_authors_on_worktree(...)` → second `update_worktree` (`zbobr-dispatcher/src/cli.rs:2168-2188`).
   - The repository backend’s `update_worktree(...)` is not a pure push; it performs merges in the worktree before pushing:
     - Phase 8: merge `origin/<work_branch>` into local worktree
     - Phase 9: merge base branch into local worktree
     - Phase 10: push (`zbobr-repo-backend-github/src/github.rs:860-881`)
   - After `git filter-branch`, the rewritten local commits have different SHAs from the already-pushed remote history. That means the remote work-branch tip is no longer an ancestor of rewritten local HEAD, so the second `update_worktree(...)` can create a **new merge commit** when it merges `origin/<work_branch>` back into the rewritten history (`merge_ref_into_worktree(...)` uses `git merge <source_ref> --no-edit` when the source is not already an ancestor: `zbobr-repo-backend-github/src/github.rs:559-588`).
   - V23’s new count-based recollection happens **before** that second `update_worktree` call. So the plan still stores only:
     - rewritten stage commits, plus
     - sync commits from the first pre-rewrite update
     but **not** the additional post-rewrite sync merge created by the second update.
   - That violates the issue’s intent to remember commits made during the stage, and it leaves at least one agent-created commit absent from context. That absent merge commit can then be misclassified later as a user commit by reviewer logic that treats commits not listed in stage context as user-made.
   - **Required fix:** the design must explicitly account for commits created by the second post-rewrite sync. Either collect/store after the second `update_worktree(...)` with a rewrite-safe strategy, or define a different push path that cannot synthesize a new merge commit after rewrite. As long as the plan stores commits before the second sync, it remains incomplete.

Minor note, not the main blocker: once `overwrite_author` switches from range-based dry-run/selection to stored stage commits, its dry-run output in `zbobr/src/commands.rs:679-694` should also be updated to show the same commit set; otherwise the command will report that it would rewrite commits that the new implementation no longer targets.

Because of the two blocking issues above, I recommend revising the plan before implementation.
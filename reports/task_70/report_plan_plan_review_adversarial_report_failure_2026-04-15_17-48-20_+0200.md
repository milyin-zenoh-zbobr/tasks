I reviewed Plan v12 against the current code in `zbobr-dispatcher/src/cli.rs`, `zbobr-utility/src/lib.rs`, `zbobr-api/src/context/mod.rs`, `zbobr-task-backend-github/src/separator.rs`, `zbobr/src/init.rs`, and `zbobr/src/commands.rs`.

The baseline-anchored idea is directionally correct for the dispatcher path: storing commits on `StageContext`, exposing them through markdown, using `git log --first-parent <baseline>..HEAD`, and collecting them after finalization for the normal/error/interruption exits all fit the existing architecture.

However, the plan is not implementation-ready yet because it leaves two important behavioral questions unresolved:

1. **The plan changes `rewrite_authors_on_worktree` globally, but one existing caller is not stage-scoped.**
   - Today `rewrite_authors_on_worktree(work_dir, dest_branch, ...)` is called both from the dispatcher finalization path and from the user-facing CLI command `task overwrite-author` in `zbobr/src/commands.rs`.
   - The dispatcher can supply a per-attempt baseline. The CLI command cannot: it currently works by rewriting `dest_branch..HEAD` for the whole task branch and printing the same range in dry-run mode.
   - Plan v12 changes the utility signature to `baseline_commit` but does not specify what the CLI command should do afterward. That is not just a missing file path; it is a missing design decision. If the worker simply renames the parameter and keeps passing the destination branch, the new “rewrite only detected stage commits” rule is violated. If the worker tries to force a stage baseline into the command, there is no defined source for it.
   - **Required revision:** either keep the current broad rewrite behavior as a separate API/command path and add a new stage-scoped helper for dispatcher use, or explicitly define how `task overwrite-author` derives its allowed rewrite range from recorded stage metadata.

2. **Retry attempts are recorded as separate stage entries, but the plan does not rewrite their commits.**
   - In the provider retry loop, each attempt pushes a new `StageContext` before execution. On `execution_failed` with remaining providers, the code `continue`s without calling `finalize_stage_session` or `perform_stash_and_push`.
   - Plan v12 proposes capturing and storing commits for that retry path before `continue`, which is good for attribution, but it does not rewrite those commits when `overwrite_author=true`.
   - Because the next attempt captures a fresh baseline from the current `HEAD`, any later `baseline..HEAD` rewrite only touches commits from the later attempt. Commits created by the failed attempt remain unrevised forever, even though they were detected as stage commits and recorded in their own `StageContext`.
   - That conflicts with the new requirement that `rewrite_authors_on_worktree` be driven by the same mechanism that determines stage-owned commits: “determine stage commits -> rewrite them if necessary -> store them to the stage record.”
   - **Required revision:** either make retry attempts go through a per-attempt rewrite/capture flow before `continue`, or explicitly change the model so failed provider attempts are not treated as separate stage executions with their own stored commit list.

Secondary concern:
- The helper sketch `capture_git_head(...) -> String /* "" on error */` is too loose for this codebase. An empty baseline is not a safe neutral value for later `git log` / rewrite ranges. The plan should require explicit error handling (propagate, or store no commits with a warning) rather than a silent empty-string fallback.

Once those two main points are resolved, the rest of the plan looks consistent with the codebase and should be implementable without major surprises.
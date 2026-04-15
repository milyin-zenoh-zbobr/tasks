I inspected the latest plan (ctx_rec_17) against the current codebase and do **not** think it is implementation-ready.

## Blocking issue 1: the proposed final `baseline..HEAD` capture still includes user commits

The plan’s main fix is to capture commits after `finalize_stage_session()` on the final attempt so it includes finalization-generated merge commits. That is necessary, but the specific mechanism is still wrong.

At stage start, the dispatcher already syncs the worktree by calling `update_worktree()` in `detect_and_handle_worktree()` before the agent runs (`zbobr-dispatcher/src/cli.rs:1629-1674`, especially `:1654`). That means the per-iteration baseline is taken *after* the branch has already incorporated the current remote state.

During finalization, `perform_stash_and_push()` calls `update_worktree()` again (`zbobr-dispatcher/src/cli.rs:2115-2189`, especially `:2168` and `:2183`). In the GitHub backend, `update_worktree()` explicitly:
1. fetches the remote work branch,
2. merges `origin/<work_branch>` into the local branch (`zbobr-repo-backend-github/src/github.rs:860-868`),
3. merges the base branch (`:870-875`), and
4. pushes the result (`:877-878`).

So if the user pushed new commits to the remote work branch while the stage was running, those commits are brought into local history during finalization. A post-finalization `git log <baseline>..HEAD --format=%h` will include **all commits reachable from HEAD but not from the baseline**, which means it will include:
- agent commits,
- finalization merge commits, and
- **user commits merged from the remote work branch**.

That directly breaks issue #314’s goal of using the context to distinguish user commits from agent/system commits. The reviewer prompt wording proposed in the plan would therefore be false in exactly the scenario this feature is meant to disambiguate.

### What the plan needs instead

The plan needs a separation strategy that excludes commits introduced only through the merged remote branch. A likely direction is to use first-parent-based collection for the final path (so merged-in remote commits are not treated as stage commits), or an equivalent explicit split between:
- commits created locally during the attempt, and
- merge commits created by finalization.

The current `baseline..HEAD` design is not sufficient.

## Blocking issue 2: the plan still drops commits on non-success finalization paths

The plan explicitly says that if `finalize_stage_session()` returns `Ok(Some(e))`, skipping commit capture is acceptable because “the stage failed anyway.” I do not agree.

In the current code, `finalize_stage_session()` still runs `perform_stash_and_push()` on interruption and on execution error (`zbobr-dispatcher/src/cli.rs:2006-2021`). That means those paths can still create or rewrite commits during finalization. But in the caller, any `Some(e)` result returns immediately before the proposed post-finalization capture point (`zbobr-dispatcher/src/cli.rs:681-699`).

This leaves a real attribution hole:
- the last failed attempt can create commits,
- finalization can merge/push/rewrite additional commits,
- the stage remains in context,
- but `stage.commits` is left incomplete or empty.

Later reviewers would then treat those unlisted commits as likely user commits even though they were created by the stage or its finalization. That is the same class of misattribution the feature is supposed to prevent.

The plan needs to cover commit attribution for all finalization paths that invoke `perform_stash_and_push()`, not only the clean-success path.

## Minor note (non-blocking by itself)

The plan correctly identifies `MdContext::from_str` as the runtime context parse path, but `MdStage` also has its own `FromStr`/serde path in `zbobr-api/src/context/mod.rs:403-441`. Since the new display format would add a `Commits:` line to `MdStage`, that parser likely needs to stay consistent too, even if it is not the main task-context deserialization path.

## Conclusion

The plan is closer, but it is still not safe to implement as written. The final commit-collection algorithm must be revised so that finalization-time collection does **not** absorb user commits merged from `origin/<work_branch>`, and the plan must cover non-success finalization paths that still perform stash/push work.
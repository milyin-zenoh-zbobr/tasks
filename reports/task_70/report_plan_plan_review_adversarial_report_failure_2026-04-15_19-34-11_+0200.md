I reviewed Plan v19 against the current code in `zbobr-utility/src/lib.rs`, `zbobr-dispatcher/src/cli.rs`, `zbobr-repo-backend-github/src/github.rs`, `zbobr-api/src/context/mod.rs`, `zbobr-api/src/task.rs`, `zbobr/src/commands.rs`, and issue #314.

The plan is much better than the previous revisions. In particular, the direction is right on:
- per-attempt baselines in the provider retry loop,
- explicit commit-set-driven author rewriting,
- post-rewrite re-collection,
- persisted full SHAs with prompt-only abbreviation,
- and separate success vs interrupted/error finalization semantics.

However, I do **not** consider v19 implementation-ready yet. Two blocking design issues remain.

## Blocking issue 1: `check_is_git_repo` still does **not** distinguish "expected no repo" from real git failures

Plan v19 claims that replacing `is_git_repo(dir) -> bool` with:

```rust
pub async fn check_is_git_repo(dir: &Path) -> Result<bool> {
    git_check(dir, &["rev-parse", "--is-inside-work-tree"]).await
}
```

solves the earlier problem because it would return:
- `Ok(true)` for a repo,
- `Ok(false)` for "git ran but not a repo",
- `Err(...)` for unexpected failures.

That is **not true** for the current utility implementation.

In `zbobr-utility/src/lib.rs:202-219`, `git_check_env` / `git_check` are documented and implemented as:
- spawn git,
- return `Err(...)` only if the process could not be started,
- return `Ok(status.success())` for **all** completed executions.

So any git command that exits non-zero becomes `Ok(false)`, not just the clean "not a git repository" case. That still collapses multiple states together:
1. expected first-run no-repo case,
2. broken/corrupt repository,
3. permission / operational git failure that still exits non-zero,
4. other unexpected rev-parse failures.

That means the proposed baseline capture site:

```rust
let attempt_baseline = match zbobr_utility::check_is_git_repo(&work_dir).await? {
    true => zbobr_utility::capture_git_head(&work_dir).await?,
    false => String::new(),
};
```

would still silently degrade real git failures into an empty baseline. The same problem remains inside `perform_stash_and_push` if it gates stash/rewrite/collection on that helper.

### Required revision
The plan needs a repo-check design that truly preserves the distinction the reviewer requested. For example:
- add a dedicated helper that inspects stderr / error kind from `git rev-parse --is-inside-work-tree` and distinguishes the specific "not a git repository" case from other failures, or
- avoid the boolean gate entirely in places where a git worktree is already expected, and treat later repo-detection failures as fatal there.

But `git_check(...) -> Result<bool>` is not sufficient with the current implementation.

## Blocking issue 2: the plan still drops commit metadata whenever stash/sync/push fails, even if the stage already made local commits

The issue requirement is to remember commits made by agents in the stage context. In v19, commit storage on finalization is still explicitly tied to `perform_stash_and_push(...)` succeeding:
- interrupted path: on failure, warn and store no commits,
- error path: on failure, warn and store no commits,
- success path: on failure, preserve the existing fatal pause behavior and store no commits.

That is still too weak for the feature’s purpose.

In the real code, `perform_stash_and_push` does much more than "discover commits":
- it stashes,
- calls `update_worktree(...)`,
- may hit merge conflicts or push failures,
- may rewrite authors,
- may fail **after** the agent has already created valid local commits.

This is visible in `zbobr-dispatcher/src/cli.rs:2166-2188`, and `update_worktree` itself can fail because merging remote work or base into the local branch conflicts (`zbobr-repo-backend-github/src/github.rs:860-878`).

Under Plan v19, if a stage produced commits locally but final sync/push fails afterward, that attempt records **no** `Commits:` metadata at all. That defeats the whole ownership-tracking goal:
- later prompts/review logic will not know those commits were agent-generated,
- user-vs-agent classification becomes wrong precisely in the conflict/manual-intervention cases where provenance matters most,
- and the stage context no longer reflects what the stage actually did.

This is not just a minor edge case. It is a direct consequence of making commit recording contingent on successful stash/sync/push completion.

### Required revision
The plan should decouple **commit detection/storage** from **push success**.

A sound architecture would be:
1. determine the attempt’s commit set from the attempt baseline,
2. rewrite that set if configured,
3. re-collect post-rewrite SHAs,
4. store them to the stage record,
5. then do the stash/sync/push outcome handling.

If push/sync later fails, keep the existing pause/warn behavior as appropriate — but do **not** lose the stage’s commit metadata just because publication failed.

## Conclusion

Plan v19 is close, but these are still implementation-blocking:
1. its new `check_is_git_repo` design still relies on `git_check`, which does not actually distinguish "not a repo" from other non-zero git failures;
2. it still makes commit persistence depend on `perform_stash_and_push` succeeding, so stages that made local commits can lose all `Commits:` metadata when final sync/push fails.

Once those two points are revised, the rest of the plan looks sound and well-aligned with the codebase.
I reviewed Plan v15 against the current code in `zbobr-dispatcher/src/cli.rs`, `zbobr-dispatcher/src/lib.rs`, `zbobr-repo-backend-github/src/github.rs`, `zbobr-utility/src/lib.rs`, `zbobr-api/src/context/mod.rs`, `zbobr/src/commands.rs`, and issue #314.

The plan is improved in two ways:
- It correctly makes retry-path rewrite failure fatal instead of warning-and-continuing.
- It correctly updates the reviewer guidance to classify commits against the union of all `Commits:` fields in the task context, not just the current stage.

However, there is still a blocking architectural problem, and it is fundamental enough that I do not consider the plan implementation-ready.

## Blocking issue 1: rewrite scope still does not match the stage-commit detection mechanism

The user’s latest requirement was explicit:
- determine stage commits
- rewrite them if necessary
- store them to the stage record

Plan v15 still leaves `rewrite_authors_on_worktree` as a revision-range rewrite (`git filter-branch ... '<lower_bound>..HEAD'`) and only renames `dest_branch` to `lower_bound`.

That is not sufficient. In Git, a range like `<baseline>..HEAD` includes **all** commits reachable from `HEAD` and not reachable from the baseline — not only the first-parent chain. But the proposed stage-commit detection is `git log --first-parent <baseline>..HEAD`, whose whole point is to exclude merged user commits.

Those two definitions do not match.

Concretely, in the current finalization flow:
- `perform_stash_and_push()` calls `update_worktree()` first.
- `update_worktree()` in `zbobr-repo-backend-github/src/github.rs` merges `origin/<work_branch>` into the local worktree and then merges the base branch.
- Under the assumption discussed in the task, user changes enter through those merges as non-first-parent history.

If author rewrite then runs on `<attempt_baseline>..HEAD`, it can still rewrite merged user commits from those second-parent sides, because they are reachable from `HEAD` and not reachable from the baseline. That directly violates the new requirement that rewrite must apply only to commits detected as belonging to the stage.

### Required revision
The plan needs to make rewrite operate on the **same commit set** produced by the stage-commit detector, not on a broad revision range.

A sound direction would be:
1. Detect the stage-owned commits using the chosen mechanism (first-parent traversal).
2. Pass that exact commit set into the rewrite mechanism.
3. Rewrite only those commits, not every commit in `<baseline>..HEAD`.
4. Re-collect/store the post-rewrite hashes in the stage record.

If `git filter-branch` is retained, its env-filter must be conditional on `GIT_COMMIT` belonging to the detected set; simply narrowing the lower bound is not enough. Also, the rewrite-target list should be based on **full SHAs** internally; short hashes are fine for context display but not as the rewrite key.

## Blocking issue 2: the existing manual `overwrite-author` command remains architecturally unsafe

`zbobr/src/commands.rs` still has the standalone overwrite-author flow, and Plan v15 explicitly preserves it by just passing `dest_branch` into the renamed `lower_bound` parameter.

That means this command would still rewrite every commit in `dest_branch..HEAD`, including merged non-agent commits, which is exactly the broader problem the user called out when they said:
> if we assume that other authors may take part in the work, it would be incorrect to rewrite their commits

So even if the dispatcher path were adjusted later, the plan still leaves an existing entry point whose behavior contradicts the new rule.

### Required revision
The planner needs to decide one of these explicitly:
1. **Bring the CLI command under the same exact-commit detection model** as the dispatcher flow, or
2. **Narrow/redefine/remove** that command so it no longer promises or performs branch-wide rewriting.

But leaving the manual path as a range-based whole-branch rewrite is not compatible with the stated requirement.

## Non-blocking observations
- The proposed `StageContext.commits` field, markdown serialization/parsing updates, and prompt-mode inclusion fix are directionally correct.
- The repository already configures git user in the worktree during setup (`ensure_worktree_github` calls `configure_git_user`), so targeted post-hoc rewrite should be treated as a corrective path, not as the primary authorship mechanism. That does not block the feature, but it reinforces that any rewrite that remains must be precise.
- The worker will need to touch more tests/fixtures than the plan’s brief file list suggests, because `StageContext` literals appear in several crates.

Because the rewrite mechanism still does not actually depend on the detected stage-commit set, and because the unsafe manual overwrite-author path remains, Plan v15 should be revised before implementation.
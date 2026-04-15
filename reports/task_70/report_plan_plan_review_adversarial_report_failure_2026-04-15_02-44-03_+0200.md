The revised plan fixes several earlier issues: it targets the real markdown parse path in `MdContext::from_str`, preserves prompt visibility for commits-only stages, and avoids the earlier per-provider baseline bug by moving capture outside the retry loop. Those parts are sound.

I still do **not** think the plan is implementation-ready, because the commit-attribution algorithm is not correct for this codebase’s actual push flow.

## Blocking issue: `origin/<base>..HEAD` count-delta after final push will over-attribute non-agent commits

The plan proposes:
1. capture `start_commit_count = rev-list --count origin/<base>..HEAD` before the retry loop,
2. after `perform_stash_and_push`, run `git log --format=%h origin/<base>..HEAD`,
3. compute `n_new = total - start_count`,
4. record the newest `n_new` hashes as this stage’s commits.

That looks plausible in isolation, but it does **not** match how finalization actually updates the worktree.

### What the code really does

`finalize_stage_session()` always calls `perform_stash_and_push()` on the completion paths (`zbobr-dispatcher/src/cli.rs:2006-2061`). Inside that function (`zbobr-dispatcher/src/cli.rs:2161-2189`), the dispatcher calls `update_worktree()` before finishing.

For the GitHub backend, `update_worktree()` is explicitly a merge-and-push flow (`zbobr-repo-backend-github/src/github.rs:734-761`):
- Phase 8 merges `origin/<work_branch>` into the local worktree (`github.rs:860-868`)
- Phase 9 merges the base branch into the local worktree (`github.rs:870-875`)
- Phase 10 pushes the result (`github.rs:877-881`)

Those merges are implemented by `merge_ref_into_worktree()` (`github.rs:559-588`), which can create real merge commits.

### Why this breaks the proposed algorithm

The final `origin/<base>..HEAD` range after `perform_stash_and_push()` is **not** just “commits created by the agent during this stage.” It can also include:

1. **User commits that arrived on `origin/<work_branch>` while the stage was running.**
   When final sync merges remote work into local work, those user commits become part of `HEAD` and therefore part of `origin/<base>..HEAD`. They were not present in the initial local baseline count, so the proposed `total - start_count` logic will count them as “new stage commits” and record them under `Commits:`.

2. **Coordinator-generated merge commits from final sync.**
   The merge of remote work or base into the worktree can create new commits during `update_worktree()`. Those are not agent-authored commits, but the count-based delta will record them as if they were.

That directly violates the issue’s purpose: the reviewer prompt is supposed to distinguish user commits from agent commits. With this plan, a user commit merged from `origin/<work_branch>` during final sync can be mislabeled as an agent commit in the context.

## Why this is architectural, not an implementation detail

This is not a small edge case or a matter of exact command flags. The current proposal is built around the wrong comparison set: **branch distance from base after final sync**. In this repository, final sync is allowed to import external commits and generate merge commits, so that set is not a reliable proxy for “commits made by the agent during the stage.”

As long as the algorithm is based on `origin/<base>..HEAD` count-delta after `perform_stash_and_push()`, the reviewer prompt will have false positives and the feature will not be trustworthy.

## Recommendation

Revise the plan one more time before implementation:

1. Keep the current domain/model/markdown direction:
   - `StageContext.commits`
   - serialization/parsing in `zbobr-api/src/context/mod.rs`
   - prompt inclusion for commits-only stages
   - reviewer-prompt update

2. Replace the **count-based delta vs base branch** with an attribution method that is anchored to the stage’s own local work, not the post-sync branch state. The design must explicitly avoid classifying:
   - commits pulled in from `origin/<work_branch>` during final sync, and
   - merge commits created by `update_worktree()`
   as agent commits.

3. Only once that attribution is authoritative should the reviewer prompt rely on `Commits:` as the source of truth for agent-vs-user commit ownership.

Until that is addressed, the plan is still not safe to implement.
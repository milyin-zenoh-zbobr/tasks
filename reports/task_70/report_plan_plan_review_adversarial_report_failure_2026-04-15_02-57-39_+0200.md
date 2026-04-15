The latest plan is **closer**, and its main GitHub-side correction is sound: capturing commits **before** `perform_stash_and_push()` avoids the earlier bug where `update_worktree()` imported user commits and merge commits before attribution. The markdown/model direction also looks correct: `StageContext.commits`, parsing in `MdContext::from_str`, prompt inclusion for commits-only stages, and the reviewer-prompt clarification all fit the codebase.

I still do **not** think the plan is implementation-ready, because its core attribution rule is written as if it were backend-agnostic, but the repository has at least two different worktree backends with materially different sync semantics.

## Blocking issue: `origin/<work_branch>..HEAD` is only stage-local on the GitHub backend

The plan’s core claim is:

- stage start sync makes local HEAD equal to `origin/<work_branch>`
- agent commits accumulate locally during the stage
- user commits only arrive during the merge step inside `perform_stash_and_push()`
- therefore `origin/<work_branch>..HEAD` captured **before** `perform_stash_and_push()` is exactly this stage’s agent commits

That is a good fit for the **GitHub backend**. In `zbobr-repo-backend-github/src/github.rs:803-878`, `update_worktree()` creates/pushes the remote work branch if needed, then merges remote work and base, and pushes the result back to origin. Under that flow, the remote work branch is indeed kept in sync across stages.

But that is **not** how the **filesystem backend** works. In `zbobr-repo-backend-fs/src/fs.rs:143-190`, `update_worktree()` only ensures the bare clone/worktree and checks whether the work branch is up to date with the base branch. It does **not** push the work branch to origin after each stage, and it does not maintain the “remote work branch mirrors the current local branch” invariant that the plan relies on.

That difference matters because `ensure_worktree()` in the FS backend reuses an existing local work branch if it already exists (`zbobr-repo-backend-fs/src/fs.rs:98-123`). If `origin/<work_branch>` does not exist there — which is normal for this backend unless someone manually created it upstream — then the plan’s fallback to `origin/<base_branch>..HEAD` becomes cumulative branch history, not “commits made during this stage.” On later stages it will keep re-reporting commits from earlier stages.

So the current plan solves the GitHub merge-flow case, but it does not solve the feature at the dispatcher level where it is being implemented.

## Why this is blocking

This is not a minor edge case or a test-only concern. The dispatcher helper in the plan would run for all backends, and the issue requirement is stage-scoped: show commits **made during this stage** so reviewers can distinguish user commits from agent commits. With the current plan, FS-backed tasks would get incorrect stage attribution.

## Recommendation

Revise the plan one more time so it explicitly handles backend differences:

1. Either **scope the commit-capture strategy to merge/push backends** that maintain `origin/<work_branch>` as a per-stage baseline, and define what happens on FS-backed tasks,
2. or use a **true per-stage baseline** that works even when the work branch is only local and never pushed to origin between stages.

Once the plan addresses that cross-backend mismatch, the rest of the current direction looks ready to implement.
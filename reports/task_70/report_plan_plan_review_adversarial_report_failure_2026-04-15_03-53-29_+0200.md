I inspected the current dispatcher/context code and do **not** think plan v11 is safe to implement yet.

The model/markdown direction is good: adding `StageContext.commits`, serializing it through `zbobr-api/src/context/mod.rs`, keeping commits-only stages visible in prompt mode, and updating the reviewer prompt all fit the codebase.

## Blocking issue: the proposed SHA baseline does not survive finalization when `overwrite_author` is enabled

The plan relies on capturing a per-attempt `commit_baseline = git rev-parse HEAD` before execution and, on the final path, recording:

- `git log --first-parent --format=%h <baseline>..HEAD`

That would work only if the baseline commit remained on the branch history. In this codebase, finalization can rewrite that history.

### Relevant code paths

1. `finalize_stage_session()` always reaches `perform_stash_and_push()` on the successful path, and also on interruption / execution-error paths before returning (`zbobr-dispatcher/src/cli.rs:2006-2061`).
2. `perform_stash_and_push()` may rewrite authors when `config.overwrite_author` is enabled (`zbobr-dispatcher/src/cli.rs:2173-2183`).
3. That rewrite is implemented by `rewrite_authors_on_worktree()` using:
   - `git filter-branch ... '<dest_branch>'..HEAD`
   which rewrites **all commits after the base branch**, not just the new stage commits (`zbobr-utility/src/lib.rs:321-372`).
4. `overwrite_author` is a real dispatcher setting, not a theoretical branch: it exists in config and defaults to false but can be enabled (`zbobr-api/src/config/mod.rs:740-766`, `zbobr/src/init.rs:344-346`).

### Why this breaks the plan

If the stage starts from work-branch commit `P2`, the plan stores `baseline = P2`. Suppose the stage creates `A1`, and finalization later runs author rewriting. Because the rewrite covers `base_branch..HEAD`, `P2`, `A1`, and finalization merge commits are all replaced with new SHAs (`P2'`, `A1'`, ...).

After that rewrite, the saved baseline `P2` is no longer on the current branch history. A later query like:

- `git log --first-parent P2..HEAD`

no longer means “commits created since this attempt started”. In practice it can include earlier first-parent commits from before the stage. I verified this behavior with a throwaway repo: after `filter-branch`, a range that previously returned only `a1` started returning `a1,p1` because the old baseline SHA was no longer reachable.

That means the plan can misattribute **pre-stage commits** as belonging to the current stage whenever `overwrite_author` is enabled. Once that happens, the proposed reviewer guidance becomes false: commits omitted from `Commits:` are not the only user commits, and commits included in `Commits:` are not guaranteed to have originated from this stage.

## Why this is blocking

This is not a small implementation detail. The whole feature is about using `Commits:` as trusted attribution for reviewer decisions. As written, the plan still anchors attribution to a mutable SHA that finalization may invalidate.

## What needs to change

Revise the plan so final commit attribution is **stable across history rewriting**. In particular:

1. Do not rely on a saved pre-stage commit SHA surviving finalization.
2. Use an attribution method that remains valid if `rewrite_authors_on_worktree()` rewrites `base_branch..HEAD`.
3. Only then update the reviewer prompt to treat `Commits:` as authoritative.

A likely direction is to base the final capture on a rewrite-stable notion of position along the branch’s first-parent chain, or otherwise split pre-rewrite local-attempt commits from post-finalization coordinator commits using data that survives the rewrite. I am not blocking on the exact command sequence, but the current SHA-range design is not robust enough for this repository.

So the plan is improved, but it is still **not implementation-ready**.
I reviewed Plan v14 against the current code in `zbobr-dispatcher/src/cli.rs`, `zbobr-utility/src/lib.rs`, `zbobr-api/src/context/mod.rs`, `zbobr-api/src/context/stage_title.rs`, `zbobr-api/src/task.rs`, `zbobr-repo-backend-github/src/github.rs`, `zbobr/src/commands.rs`, and issue #314.

The plan fixes the two blockers from v13 correctly:
- `StageContext` is indeed attempt-scoped today (`zbobr-dispatcher/src/cli.rs` pushes a new stage entry inside the provider retry loop, and `stage_title.rs` encodes tool/model/timestamp per attempt), so moving to a per-attempt baseline is the right architectural correction.
- Using `git log --first-parent <baseline>..HEAD` matches the current `update_worktree` merge shape in `zbobr-repo-backend-github/src/github.rs`: upstream changes arrive through `git merge ... --no-edit`, so first-parent traversal is a reasonable separator under the stated assumption that user changes only arrive through merges.

However, I still see two blocking issues.

1. **Retry-path author rewrite failure is treated as non-fatal, but earlier-attempt commits cannot be repaired later.**
   - In the proposed retry-path snippet, `rewrite_authors_on_worktree(...)` is wrapped in `if let Err(e) = ... { tracing::warn!(...) }`, then the loop continues to the next provider.
   - That is not safe under the new requirement. For a failed attempt, the plan intentionally rewrites that attempt’s commits *before* `continue`, because the final-attempt rewrite only covers the last attempt’s `attempt_baseline..HEAD` range.
   - If the retry-path rewrite fails and execution still continues, those earlier-attempt commits keep their original authors, and the later finalization path does **not** revisit them. So the task can complete with incorrect author metadata for commits that were already classified as stage-owned.
   - This is inconsistent with the current finalization behavior, where rewrite failure propagates out of `perform_stash_and_push` instead of being silently downgraded to a warning.
   - **Required revision:** make retry-path rewrite failure explicit and durable. Either pause/fail the stage when a required rewrite fails, or design a later guaranteed rewrite pass that still covers those already-attributed retry commits. But “warn and continue” is not implementation-safe here.

2. **The reviewer-prompt wording still uses per-stage wording where the task requires branch-wide / context-wide classification.**
   - Issue #314 says reviewer guidance should make clear that user commits are the commits **not mentioned in the context**.
   - Plan v14 proposes: “commits listed under a stage’s `Commits:` field are known agent and system commits for that execution attempt ... any commit not listed there was likely introduced by the user.”
   - That is too narrow. The reviewer works from `git diff origin/<destination_branch>...HEAD` / branch history, which spans the whole task branch, not just one execution attempt. Commits from earlier stages or earlier attempts may be absent from the *current* stage’s `Commits:` field but still be agent commits recorded elsewhere in the context.
   - With the wording as written, a worker could implement prompt guidance that misclassifies agent commits from other stages as “user” simply because they are not listed under the stage currently being discussed.
   - **Required revision:** phrase the prompt in terms of the union of commit hashes recorded anywhere in the task context (for example: commits listed in any stage `Commits:` field are known agent/system commits; commits absent from all such lists are likely user-introduced).

Minor observations, not blocking by themselves:
- Adding `commits` to `StageContext` will require touching more tests/fixtures than the file list suggests; that is expected, but the worker should budget for it.
- The markdown/parser changes are directionally sound. `MdContext::from_str` does need explicit handling for the new `Commits:` line because `parse_context()` does not go through `MdStage::from_str`.

Because of the two issues above, I do **not** consider Plan v14 implementation-ready yet. The next revision should keep the per-attempt baseline model, but make retry-path rewrite failure non-silent and update the reviewer prompt to classify commits against the full context, not a single stage entry.
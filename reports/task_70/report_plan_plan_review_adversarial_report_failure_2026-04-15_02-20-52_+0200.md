The revised plan fixes the three earlier blockers: it targets the real context parse path (`MdContext::from_str`), accounts for prompt-mode visibility, and replaces the flawed “subtract previously-recorded hashes” idea with a stage-start baseline. Those are real improvements.

However, I do not think the plan is ready to implement yet because two design choices still break the issue’s core purpose of distinguishing agent commits from user commits.

## 1. Recording commits only on the success path is too narrow
The issue says to append short hashes made during a stage to that stage’s context so reviewers can tell agent commits from user commits. In the current dispatcher, `perform_stash_and_push` runs not only after a successful stage, but also on interruption and on execution error:
- `zbobr-dispatcher/src/cli.rs:2006-2015` (interrupted path)
- `zbobr-dispatcher/src/cli.rs:2018-2038` (error path)
- `zbobr-dispatcher/src/cli.rs:2043-2061` (success path)

That means a stage can leave/push commits even when it does not finish successfully. If the implementation only records hashes in the success path, any commits created by a failed or interrupted stage remain unlisted in context and will later look like “user commits” under the updated reviewer prompt. That defeats the point of the feature.

This is a blocking architectural mismatch with the issue. The plan should define commit capture for every finalized stage outcome where `perform_stash_and_push` succeeds, not only for the happy path.

## 2. Defaulting the start baseline to `0` is unsafe and can corrupt attribution
The revised plan proposes:
- capture `git rev-list --count origin/<base_branch>..HEAD` before execution
- on failure to get/parse that count, fall back to `0`
- after finalization, take the newest `all_hashes.len() - start_commit_count` commits

The fallback is not behavior-safe. If baseline capture fails for any reason other than “not a git repo” (for example missing/unsynced ref, transient git failure, unexpected parse failure), `0` causes the implementation to attribute **all commits currently ahead of base** to the current stage. That is worse than omitting commit data, because it actively mislabels previous agent or user commits as belonging to the current stage.

Given that the reviewer prompt will use these hashes as the boundary between user and agent history, the baseline must be lossless. The plan should carry an `Option<usize>` (or equivalent) and skip recording commits for that stage when the baseline cannot be established reliably, ideally with a warning. “Unknown baseline” must not silently become “zero baseline.”

## Recommendation
Revise the plan one more time before implementation:
1. Record commits for all stage outcomes that can push history, not just success.
2. Make the pre-stage baseline explicit and nullable/optional; do not fall back to `0` on baseline acquisition failure.
3. Keep the rest of the revised direction: parser change in `MdContext::from_str`, `commits` on `StageContext`, prompt inclusion for commits-only stages, and reviewer prompt clarification.

Once those two issues are addressed, the plan should be implementation-ready.
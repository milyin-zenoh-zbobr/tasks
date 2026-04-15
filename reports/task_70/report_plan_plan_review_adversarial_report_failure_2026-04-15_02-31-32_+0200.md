The revised plan fixes several earlier problems: it targets the real parse path in `MdContext::from_str`, preserves prompt visibility for commits-only stages, and no longer uses the dangerous `0` baseline fallback. Those are good corrections.

I still do **not** think the plan is implementation-ready, because one remaining architectural gap breaks the feature’s core purpose, and a second design choice leaves the updated reviewer prompt semantically unsound.

## 1. The plan still under-scopes commit attribution to the final attempt, but stage context is created per provider attempt

In `run_session`, a new `StageContext` is pushed **inside the provider retry loop** before each execution attempt (`zbobr-dispatcher/src/cli.rs:532-560`). If an attempt fails with `execution_failed`, the code can `continue` to the next provider/model without calling `finalize_stage_session` (`zbobr-dispatcher/src/cli.rs:649-670`). `finalize_stage_session` is only reached after the loop decides not to retry (`zbobr-dispatcher/src/cli.rs:681-691`).

That means the current plan’s commit-recording design only covers the **last** attempt that reaches `finalize_stage_session`, even though earlier failed attempts already have their own persisted stage records in context.

Why this is blocking:
- A failed provider attempt can still make commits before exiting non-zero.
- Those commits remain in the worktree and may later be pushed by a subsequent successful attempt.
- The plan’s per-attempt baseline is captured anew for the later attempt, so the earlier attempt’s commits are now part of the later baseline and will never be recorded under any stage record.
- Under the proposed reviewer prompt, those unlisted commits will be treated as “user commits,” which is wrong.

This is not a corner case; it follows directly from the existing retry architecture. The plan needs a strategy that works with **multiple StageContext entries for the same logical stage**. For example, it could:
1. keep baseline metadata per attempt and, after the final push/rewrite, assign the final hash ranges back to each attempt’s stage record, or
2. explicitly finalize each failed attempt before retry in a way that is compatible with later author-rewrite / push behavior.

But in its current form, the plan does not solve attribution for earlier failed attempts, so it does not satisfy the issue’s main goal.

## 2. `Option<usize>` + silent skip still makes the reviewer prompt’s new rule unreliable

The plan now proposes `start_commit_count: Option<usize>` and says that if baseline capture fails, commit recording should be skipped for that stage. That is safer than coercing the baseline to `0`, but it still conflicts with the planned prompt change.

The reviewer prompt update says, in effect: commits not mentioned in any stage `Commits:` line are user commits. That only works if commit recording is treated as authoritative. But the plan explicitly allows a stage to have missing commit data due to transient git/count/log failures, and then still wants the reviewer to interpret absence as proof of user ownership.

That leaves the design internally inconsistent:
- dispatcher side: “if capture fails, omit commit attribution for this stage”
- reviewer side: “if a commit is omitted from stage attribution, it is a user commit”

Those cannot both be true. If the plan wants omission to remain possible, then the reviewer prompt cannot define all unlisted commits as user commits. If the prompt definition must stay strong, then the capture design needs an explicit ‘unknown attribution’ representation rather than silent omission.

## Recommendation

Revise the plan one more time before implementation:

1. Address **provider retries explicitly**. The design must account for the fact that `run_session` creates a separate `StageContext` per attempt, while earlier failed attempts can still leave commits that are later pushed.
2. Resolve the **missing-data semantics**. Either:
   - make commit capture authoritative enough that omission does not happen silently in normal operation, or
   - add an explicit ‘unknown attribution’ state / wording so the reviewer prompt does not equate ‘not listed’ with ‘user commit’ when capture was skipped.
3. Keep the rest of the current direction: `StageContext.commits`, markdown serialization/parsing in `MdContext::from_str`, prompt inclusion for commits-only stages, and reviewer-prompt clarification.

Once those two issues are addressed, the plan should be ready for implementation.
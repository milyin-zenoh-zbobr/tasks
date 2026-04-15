Plan v13 has been submitted. Here's a summary of the key design decisions that resolve the two blocking gaps from v12:

**Gap 1 (`task overwrite-author` command):** Rename `dest_branch` → `lower_bound` in `rewrite_authors_on_worktree`. The CLI command continues passing `dest_branch` unchanged. The dispatcher passes `stage_baseline` SHA. No split API needed — the function is identical, only the caller's input differs.

**Gap 2 (retry path commits not rewritten):** Capture `stage_baseline` *once* before the retry loop (not per attempt). This means:
- All provider-attempt commits (`A1, A2` from attempt 1 + `B1, B2` from attempt 2) fall within `stage_baseline..HEAD` and get rewritten together in the single `perform_stash_and_push` call.
- Failed retry `StageContext` entries keep `commits: Vec::new()` — no per-attempt capture. Only the final `StageContext` entry gets the full commit list captured after `finalize_stage_session`.

**Secondary concern:** `capture_git_head` returns `anyhow::Result<String>`. On error, `stage_baseline` is set to `String::new()` and commit capture is skipped safely.
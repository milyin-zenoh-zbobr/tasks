# Plan v15: Show Commits in Context (Issue #314)

## Context

This feature records per-attempt agent commits in `StageContext.commits` so reviewers can distinguish agent commits from user commits when reviewing branch history. Plans v11–v14 established the per-attempt baseline model, markdown serialization, and `--first-parent` traversal. Plan v14 was nearly complete; two blocking issues remained (ctx_rec_27):

**Issue 1 — Retry-path rewrite failure treated as non-fatal (blocking):** Plan v14 wrapped the retry-path `rewrite_authors_on_worktree` call in `if let Err(e) = ... { warn }`. This is unsafe: if the rewrite fails, those commits keep wrong authors, and the final `perform_stash_and_push` rewrite only covers `attempt_baseline..HEAD` (the last attempt's range), so earlier attempt commits are never corrected. The reviewer required that rewrite failure on the retry path be made fatal/durable.

**Issue 2 — Reviewer prompt uses per-stage commit classification (blocking):** Plan v14 proposed to tell the reviewer "commits listed under a stage's `Commits:` field are known agent commits". But the reviewer works from `git diff origin/<destination_branch>...HEAD`, which spans the full task branch including multiple stages and attempts. Commits from earlier stages would be absent from the current stage's `Commits:` but are still agent commits recorded in other stages. The reviewer required that the prompt reference commits from the union of ALL `Commits:` fields across the entire task context.

---

## Changes Relative to Plan v14

Plan v15 keeps all of Plan v14 unchanged except for the two targeted fixes below.

### Fix 1: Make retry-path author rewrite failure fatal

In the retry path (step 4e of Plan v14), change:
```
if let Err(e) = rewrite_authors_on_worktree(...).await {
    tracing::warn!("...");
}
```
to:
```
rewrite_authors_on_worktree(...).await?;
```

This propagates rewrite failure as an error out of the retry loop, failing the stage. It is consistent with the existing `perform_stash_and_push` behavior where `rewrite_authors_on_worktree(...).await?` already propagates errors on the final path. The guard `if !attempt_baseline.is_empty() && config.overwrite_author` remains — the rewrite is only attempted when conditions are met, and only then is the error treated as fatal.

### Fix 2: Update reviewer prompt to reference the full context's commits

In `zbobr/src/init.rs`, in the `REVIEWER_PROMPT` (around step 5 / reviewing user vs agent changes), replace the per-stage commit classification wording with:

> Commits listed in any `Commits:` field anywhere in the task context (across all stages and all retry attempts) are known agent and system commits. Commits absent from ALL such lists are likely user-introduced and should be accepted as-is.

This ensures the reviewer agent correctly classifies commits from all stages and attempts when looking at the full branch history.

---

## Full Architecture (unchanged from Plan v14 except the two fixes above)

### 1. Domain model — `zbobr-api/src/task.rs`

Add to `StageContext`:
```rust
#[serde(default, skip_serializing_if = "Vec::is_empty")]
pub commits: Vec<String>,
```
Update the `StageContext { ... }` constructor at `zbobr-dispatcher/src/cli.rs:545` to include `commits: Vec::new()`.

### 2. Utility function — `zbobr-utility/src/lib.rs` (line 327)

Rename parameter `dest_branch: &str` → `lower_bound: &str` in `rewrite_authors_on_worktree`. Update the git filter-branch range string and doc comment. This allows both callers: CLI passes a branch name; dispatcher passes a commit SHA.

### 3. Markdown serialization — `zbobr-api/src/context/mod.rs`

- Add `const COMMITS_LABEL: &str = "Commits"`.
- Add `commits: Vec<String>` to `MdStage` struct.
- `MdStage::from_stage_context`: add `commits: stage.commits.clone()`.
- `MdStage::into_stage_context`: add `commits: self.commits`.
- `MdStage` Display: emit `  Commits: \`abc1234\` \`def5678\`` when non-empty.
- `MdStage::from_str`: detect `COMMITS_LABEL` line, parse backtick-wrapped tokens into `commits`.
- `MdContext::from_str`: detect `COMMITS_LABEL` line, parse into current stage's `commits`.
- Prompt-mode skip fix: `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }`.

### 4. Commit capture and wiring — `zbobr-dispatcher/src/cli.rs`

**New helpers:**
```rust
async fn capture_git_head(dir: &Path) -> anyhow::Result<String>
async fn collect_agent_commits(dir: &Path, baseline: &str) -> Vec<String>
    // guard: if baseline.is_empty() { return Vec::new() }
    // git log --first-parent --format=%h <baseline>..HEAD
    // on error: warn, return Vec::new()
```

**`perform_stash_and_push`** (line 2115): add `commit_baseline: &str` parameter. Replace `&base_branch` in the `rewrite_authors_on_worktree` call with `commit_baseline`. Add guard: `&& !commit_baseline.is_empty()`. Update all three callers in `finalize_stage_session`.

**`finalize_stage_session`** (line ~1994): add `commit_baseline: &str` parameter, thread through to all three `perform_stash_and_push` calls.

**Per-attempt baseline** (before StageContext push at line 532):
```rust
let attempt_baseline = capture_git_head(&work_dir).await.unwrap_or_else(|e| {
    tracing::warn!("Failed to capture git HEAD: {e}");
    String::new()
});
```

**Retry path** (before `continue` at line 670):
```rust
if !attempt_baseline.is_empty() && config.overwrite_author {
    zbobr_utility::rewrite_authors_on_worktree(
        &work_dir, &attempt_baseline, &config.git_user_name, &config.git_user_email,
    ).await?;  // ← fatal on error (Fix 1)
}
let retry_commits = collect_agent_commits(&work_dir, &attempt_baseline).await;
role_session.modify_task(|mut task| {
    if let Some(stage) = task.context.stages.last_mut() { stage.commits = retry_commits; }
    task
}).await.unwrap_or_else(|e| tracing::warn!("Failed to store retry commits: {e}"));
continue;
```

**Final path** (after `finalize_stage_session`):
```rust
let finalize_result = self.zbobr.finalize_stage_session(..., &attempt_baseline).await?;
let all_commits = collect_agent_commits(&work_dir, &attempt_baseline).await;
role_session.modify_task(|mut task| {
    if let Some(stage) = task.context.stages.last_mut() { stage.commits = all_commits; }
    task
}).await.unwrap_or_else(|e| tracing::warn!("Failed to store final commits: {e}"));
if let Some(e) = finalize_result { server_handle.abort(); return Err(e); }
server_handle.abort();
return Ok(());
```

### 5. CLI command caller — `zbobr/src/commands.rs` (line 659)

Update call to pass `dest_branch` as the renamed `lower_bound` parameter. No behavior change.

### 6. Reviewer prompt — `zbobr/src/init.rs`

Add guidance to `REVIEWER_PROMPT` (after step 5 or as a note in the diff-inspection step):

> When classifying commits as agent vs user: commits whose hashes appear in ANY `Commits:` field anywhere in the task context (across all stages and all retry attempts) are known agent/system commits. Commits absent from all such lists are likely user-introduced and should be accepted as-is without questioning them.

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext` |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL`; `commits` in `MdStage`; Display; from_str; from/into_stage_context; prompt-mode fix |
| `zbobr-utility/src/lib.rs` | Rename `dest_branch` → `lower_bound` in `rewrite_authors_on_worktree` |
| `zbobr-dispatcher/src/cli.rs` | Two new helpers; per-attempt baseline inside loop; retry-path fatal rewrite + commit capture before `continue`; `commit_baseline` param chain through `finalize_stage_session` → `perform_stash_and_push`; final-path commit capture after finalization |
| `zbobr/src/commands.rs` | Update call site for renamed parameter |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` to classify commits against union of all context `Commits:` fields |

---

## Key Design Decisions

**Why make retry-path rewrite failure fatal?**
Failing the stage on rewrite failure is the only safe option without redesigning the baseline model. The alternative (defer all rewriting to finalization with `stage_baseline..HEAD`) would require the final rewrite to cover all attempts' commits — but then SHAs stored in retry StageContexts would be stale after rewriting. Making it fatal is consistent with `perform_stash_and_push` behavior and avoids stale SHAs.

**Why `--first-parent` in `collect_agent_commits`?**
User insight: "all stage commits are always local and any user commits may only come on merging." `update_worktree` merges user commits as second parents. `--first-parent` follows only the local-branch chain, excluding user commits.

**Why capture AFTER `finalize_stage_session` for the final path?**
`finalize_stage_session` calls `perform_stash_and_push` → `update_worktree` (creating finalization merge commits). These system merge commits must appear in `Commits:`. Capturing before would miss them.

**Why union of all context `Commits:` fields in the reviewer prompt?**
The reviewer's `git diff` spans the full task branch — multiple stages and retry attempts. Using only the current stage's `Commits:` would misclassify agent commits from other attempts as user-introduced.

---

## Verification

1. `cargo build` — no compile errors; verify all `rewrite_authors_on_worktree` call sites compile.
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Roundtrip: `StageContext` with commits → markdown → parse back → equal.
   - Backward compat: empty commits → no `Commits:` line; parsing without `Commits:` → empty.
   - Prompt inclusion: stage with commits but no records is NOT skipped in prompt mode.
3. Integration: run a stage that triggers a provider retry.
   - Verify retry StageContext has its own commits (non-empty, scoped to that attempt).
   - Verify final StageContext has its own commits including finalization merge commits.
4. Integration: rewrite failure on retry path (`overwrite_author=true`, simulate rewrite failure) → verify stage fails rather than silently continuing with wrong authors.

# Plan v14: Show Commits in Context (Issue #314)

## Context

This feature records per-stage agent commits in `StageContext.commits` so reviewers can distinguish
agent commits from user commits. Plans v11–v13 established the model and markdown serialization
approach. Two blocking issues remain (ctx_rec_25):

**Issue 1 — Retry attribution inconsistency:** Plan v13 used a single `stage_baseline` captured
before the retry loop, with failed attempts keeping `commits: []` and the final attempt's
StageContext receiving all commits from `stage_baseline..HEAD`. The adversarial reviewer correctly
flagged this as misattribution: commits produced by provider A / model A during attempt 1 would
appear in the StageContext that lists provider B / model B. The reviewer required that one of two
explicit model changes be made.

**Issue 2 — Empty baseline unsafe for rewriting:** Plan v13 proposed returning `""` from
`capture_git_head` on error, then threading that empty string as `lower_bound` to
`rewrite_authors_on_worktree`. An empty `lower_bound` produces a malformed git range
(`''..HEAD`). The reviewer requires explicit safe handling when no baseline is available.

---

## Resolution

### Issue 1: Per-attempt baseline + per-attempt rewrite/capture

Choose option 1 from the reviewer's alternatives: keep the existing per-attempt StageContext model
and capture/rewrite/store commits per-attempt before each `continue`.

- Capture `attempt_baseline = git rev-parse HEAD` **inside the retry loop**, before pushing
  StageContext (HEAD doesn't change between provider selection and StageContext push).
- On **retry path** (execution_failed && attempts_remaining > 0 → `continue`):
  - If `overwrite_author=true` and baseline is non-empty: call
    `rewrite_authors_on_worktree(work_dir, attempt_baseline, ...)` locally (no push).
  - Collect commits: `git log --first-parent --format=%h attempt_baseline..HEAD`.
  - Store in this attempt's `StageContext.commits`.
  - Then `continue`.
- On **final path** (after `finalize_stage_session`):
  - Pass `attempt_baseline` (the last iteration's baseline) to `finalize_stage_session` →
    `perform_stash_and_push`. The rewrite in `perform_stash_and_push` uses `attempt_baseline`
    as the lower bound, covering only this attempt's commits.
  - After `finalize_stage_session` returns (bind result first), collect `attempt_baseline..HEAD
    --first-parent` and store in the final StageContext.

This makes each StageContext's `commits` list contain exactly the commits from its own execution
attempt — correct attribution for all retry and final-attempt scenarios.

### Issue 2: Safe empty-baseline handling

`capture_git_head` returns `anyhow::Result<String>`. On error: log a warning, set
`attempt_baseline = String::new()`. All subsequent operations guard on `!baseline.is_empty()`:
- Retry-path rewrite: skipped when baseline empty.
- `perform_stash_and_push`: skipped when baseline empty (add guard around the
  `rewrite_authors_on_worktree` call; currently that call uses `&base_branch` which is always
  valid, so the guard is purely a new addition).
- `collect_agent_commits`: returns `Vec::new()` immediately when baseline empty.

---

## Architecture

### 1. Domain model — `zbobr-api/src/task.rs`

Add to `StageContext` (line ~180):
```
#[serde(default, skip_serializing_if = "Vec::is_empty")]
pub commits: Vec<String>,
```
Update the `StageContext { ... }` push at `zbobr-dispatcher/src/cli.rs:545` to include
`commits: Vec::new()`.

### 2. Utility function — `zbobr-utility/src/lib.rs` (line 327)

Rename parameter `dest_branch: &str` → `lower_bound: &str` in `rewrite_authors_on_worktree`.
Update the filter-branch range string accordingly. Update doc comment. This allows both callers:
CLI command passes a branch name; dispatcher passes a commit SHA. Behavior is identical at the
git level.

### 3. Markdown serialization — `zbobr-api/src/context/mod.rs`

- **3a.** Add `const COMMITS_LABEL: &str = "Commits"` at module level (avoids repeated string
  literals).
- **3b.** Add `commits: Vec<String>` to `MdStage` struct.
- **3c.** `MdStage::from_stage_context` (~line 446): add `commits: stage.commits.clone()`.
- **3d.** `MdStage::into_stage_context` (~line 486): add `commits: self.commits`.
- **3e.** `MdStage` Display: after the records loop, if `commits` is non-empty, emit
  `  Commits: \`abc1234\` \`def5678\`` (two-space indent, backtick-wrapped short SHAs).
- **3f.** `MdStage::from_str` (~line 403): detect `trimmed.starts_with(COMMITS_LABEL)` and parse
  backtick-wrapped tokens into `commits`.
- **3g.** `MdContext::from_str` (~line 547): detect `COMMITS_LABEL` line, parse backtick-wrapped
  tokens into current stage's `commits`.
- **3h.** Prompt-mode skip fix in `MdContext::from_task_context` (~line 651):
  - Old: `if for_prompt && md_stage.records.is_empty() { continue; }`
  - New: `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }`

### 4. Commit capture and wiring — `zbobr-dispatcher/src/cli.rs`

**4a. Two new private async helpers** (using existing `git_output` from `zbobr_utility`):

```rust
async fn capture_git_head(dir: &Path) -> anyhow::Result<String>
    // git rev-parse HEAD → Ok(trimmed sha), or Err

async fn collect_agent_commits(dir: &Path, baseline: &str) -> Vec<String>
    // guard: if baseline.is_empty() { return Vec::new() }
    // git log --first-parent --format=%h <baseline>..HEAD
    // on error: warn, return Vec::new()
```

**4b. `perform_stash_and_push`** (line 2115): add `commit_baseline: &str` parameter. Replace the
existing `&base_branch` in the `rewrite_authors_on_worktree` call with `commit_baseline`. Add
guard: `&& !commit_baseline.is_empty()` next to existing `&& is_uptodate && is_git_repo` guard.
(All three existing callers of `perform_stash_and_push` in `finalize_stage_session` must be
updated to pass the new parameter.)

**4c. `finalize_stage_session`** (line ~1994): add `commit_baseline: &str` parameter. Thread
through to all three `perform_stash_and_push` calls (interruption path, error path, success path).

**4d. Per-attempt baseline — inside the retry loop** (before line 532 StageContext push):
```rust
let attempt_baseline = capture_git_head(&work_dir).await.unwrap_or_else(|e| {
    tracing::warn!("Failed to capture git HEAD for commit tracking: {e}");
    String::new()
});
```

**4e. Retry path** (after `server_handle.abort()`, before `continue` at line 670):
```rust
// Rewrite authors for this attempt's commits (local only, no push)
if !attempt_baseline.is_empty() {
    let config = self.zbobr.config();
    if config.overwrite_author {
        if let Err(e) = zbobr_utility::rewrite_authors_on_worktree(
            &work_dir, &attempt_baseline,
            &config.git_user_name, &config.git_user_email,
        ).await {
            tracing::warn!("Author rewrite failed for retry attempt of task #{}: {e}", self.task_id);
        }
    }
}
// Capture and store commits for this attempt
let retry_commits = collect_agent_commits(&work_dir, &attempt_baseline).await;
let role_session = self.zbobr.role_session(self.task_id);
role_session.modify_task(move |mut task| {
    if let Some(stage) = task.context.stages.last_mut() {
        stage.commits = retry_commits;
    }
    task
}).await.unwrap_or_else(|e| tracing::warn!("Failed to store retry commits: {e}"));
continue;
```

**4f. Final path** — restructure the `finalize_stage_session` call (lines 681-695):
```rust
let finalize_result = self.zbobr.finalize_stage_session(
    self.task_id, self.pipeline, self.stage, &work_dir,
    outcome, last_mapped_tool, &attempt_baseline,
).await?;

// Capture AFTER finalization — includes system merge commits from update_worktree.
// --first-parent excludes user commits (second parents of merge commits).
let all_commits = collect_agent_commits(&work_dir, &attempt_baseline).await;
let role_session = self.zbobr.role_session(self.task_id);
role_session.modify_task(move |mut task| {
    if let Some(stage) = task.context.stages.last_mut() {
        stage.commits = all_commits;
    }
    task
}).await.unwrap_or_else(|e| tracing::warn!("Failed to store final commits: {e}"));

if let Some(e) = finalize_result {
    server_handle.abort();
    return Err(e);
}
server_handle.abort();
return Ok(());
```

### 5. CLI command caller — `zbobr/src/commands.rs` (line 659)

Update `rewrite_authors_on_worktree` call to pass `dest_branch` as the renamed `lower_bound`
parameter. No behavior change; only the parameter name changed in the utility signature.

### 6. Reviewer prompt — `zbobr/src/init.rs`

Update REVIEWER_PROMPT step 5: commits listed under a stage's `Commits:` field are known agent
and system commits for that execution attempt (including finalization merge commits); any commit
not listed there was likely introduced by the user and should be accepted.

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext` |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL`; `commits` in `MdStage`; Display; from_str; from/into_stage_context; prompt-mode fix |
| `zbobr-utility/src/lib.rs` | Rename `dest_branch` → `lower_bound` in `rewrite_authors_on_worktree` |
| `zbobr-dispatcher/src/cli.rs` | Helpers; per-attempt baseline inside loop; retry-path rewrite + capture before `continue`; `commit_baseline` param chain through `finalize_stage_session` → `perform_stash_and_push`; restructured final-path capture |
| `zbobr/src/commands.rs` | Update call site to match renamed parameter |
| `zbobr/src/init.rs` | Update REVIEWER_PROMPT step 5 |

---

## Key Design Decisions

**Why per-attempt baseline inside the loop (not before the loop)?**
Each StageContext entry is per-attempt. Per-attempt baseline scopes attribution correctly: commits
from attempt 1 (provider A / model A) appear only in StageContext 1, not in StageContext 2. This
resolves the reviewer's blocking issue 1.

**Why rewrite locally on the retry path (no push)?**
On the retry path, we don't push at all — failed attempts are never pushed individually. The local
rewrite ensures that when finalization eventually pushes everything, the retry-attempt commits
already carry the correct author. The final-attempt rewrite in `perform_stash_and_push` only covers
`attempt_baseline..HEAD` (the last attempt), which is correct because prior-attempt commits were
already locally rewritten.

**Why capture after `finalize_stage_session` for the final path?**
`finalize_stage_session` calls `perform_stash_and_push` which calls `update_worktree` (creating
finalization merge commits M1, M2). These system merge commits must appear in `Commits:`. Capturing
before finalization would miss them.

**Why `--first-parent` in `collect_agent_commits`?**
User insight: "all stage commits are always local and any user commits may come only on merging."
`update_worktree` merges user commits as second parents of M1, M2. `--first-parent` follows only
the local-branch chain [A1, A2, M1, M2], excluding user commits (second parents of M1/M2).

**Why rename `dest_branch` → `lower_bound` (not split the function)?**
The utility logic is identical — only the lower bound's source differs per caller. Splitting
would duplicate code without behavioral benefit.

**Why not use `""` as a safe sentinel for empty baseline?**
An empty string passed as `'<lower_bound>'..HEAD` to git filter-branch is not a valid git range
and produces undefined behavior. All uses guard on `!baseline.is_empty()` explicitly.

---

## Verification

1. `cargo build` — no compile errors; grep all callers of `rewrite_authors_on_worktree` to
   confirm both compile correctly with renamed parameter.
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Roundtrip: `StageContext` with commits → markdown → parse back → equal.
   - Backward compat: empty commits → no `Commits:` line; parsing markdown without `Commits:` →
     empty commits.
   - Prompt inclusion: stage with commits but no records is NOT skipped in prompt mode.
3. Integration check with `overwrite_author=true`:
   - Run a stage that triggers at least one provider retry.
   - Verify retry StageContext has its own commits (not empty, not including final-attempt commits).
   - Verify final StageContext has its own commits including finalization merge commits.
   - Verify `git log attempt_baseline..HEAD` post-finalization matches stored SHAs.
4. Integration check with `overwrite_author=false`:
   - Verify `Commits:` in context markdown contains correct SHAs.
   - Verify SHAs are stable (no rewriting alters them).

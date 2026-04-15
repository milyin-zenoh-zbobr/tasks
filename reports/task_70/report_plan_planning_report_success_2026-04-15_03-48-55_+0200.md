# Plan v11: Show Commits in Context (Issue #314)

## Problem Analysis

The feature records agent/system commits in `StageContext.commits` so reviewers can distinguish agent commits from user commits. Two blocking issues identified in ctx_rec_18:

**Blocking Issue 1 — User commit inclusion in final capture:**
During `finalize_stage_session() → perform_stash_and_push() → update_worktree()`, the GitHub backend:
1. Fetches `origin/<work_branch>`
2. Merges `origin/<work_branch>` into local work → creates merge commit M1 (user commits become M1's second parent)
3. Merges base branch into local work → creates merge commit M2
4. Pushes result

A plain `baseline..HEAD` log walks ALL parents, so user commits U1 (second parent of M1) appear in the output. This is the opposite of what's wanted.

**Fix:** Use `git log --first-parent --format=%h baseline..HEAD`. With first-parent traversal:
- Local branch DAG: `baseline → A1 → A2 → M1 → M2 → HEAD`
- M1's first parent: A2 (local); second parent: U1 (user commit from remote)  
- First-parent gives: `A1, A2, M1, M2` ✓ (merge commits appear; their merged-in user commits don't)

**Blocking Issue 2 — Non-success finalization paths drop commits:**
`finalize_stage_session()` runs `perform_stash_and_push()` on interruption path AND on execution-error path, then returns `Ok(None)` or `Ok(Some(e))` respectively. The previous plan used:
```rust
if let Some(e) = self.zbobr.finalize_stage_session(...).await? {
    server_handle.abort();
    return Err(e);  // early return — post-finalization capture never reached
}
// commit capture was here — missed by Ok(Some(e)) path
```

**Fix:** Restructure caller to bind the result first, capture commits for ALL outcomes, then check:
```rust
let finalize_result = self.zbobr.finalize_stage_session(...).await?;
// capture commits here — runs for interruption, error, and success
if let Some(e) = finalize_result {
    server_handle.abort();
    return Err(e);
}
```

---

## Architecture Plan

### 1. Domain model — `zbobr-api/src/task.rs`

Add `commits: Vec<String>` to `StageContext`:
```rust
#[serde(default, skip_serializing_if = "Vec::is_empty")]
pub commits: Vec<String>,
```
Update the `StageContext { ... }` construction site in `zbobr-dispatcher/src/cli.rs` (~line 545) to include `commits: Vec::new()`.

### 2. Markdown serialization — `zbobr-api/src/context/mod.rs`

**2a.** Add `commits: Vec<String>` to `MdStage` struct.

**2b.** Add module-level `const COMMITS_LABEL: &str = "Commits"` to avoid string divergence (per project rule 1: avoid repeated string literals).

**2c.** `MdStage::Display`: after the records loop, if `commits` is non-empty, emit:
```
  Commits: `abc1234` `def5678`
```
(two-space indent, backtick-wrapped SHAs). Emit in both prompt and non-prompt modes.

**2d.** `MdStage::from_str` (line ~403): in the per-line loop, detect `trimmed.starts_with(COMMITS_LABEL)` and parse backtick-wrapped tokens into `commits`. This keeps `MdStage::from_str` consistent with its Display output (even though this isn't the primary deserialization path, keeping it consistent avoids subtle bugs).

**2e.** `MdContext::from_str` (line ~547): between the `MdRecord::try_parse` check and the `"- "` stage-title check, add detection for `COMMITS_LABEL` line and parse backtick-wrapped tokens into `stage.commits`. This IS the primary runtime deserialization path.

**2f.** `MdStage::from_stage_context` (line ~446): add `commits: stage.commits.clone()`.

**2g.** `MdStage::into_stage_context` (line ~486): add `commits: self.commits`.

**2h.** Prompt-mode inclusion fix in `MdContext::from_task_context` (line ~651):
- Old: `if for_prompt && md_stage.records.is_empty() { continue; }`
- New: `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }`

### 3. Commit capture — `zbobr-dispatcher/src/cli.rs`

**3a.** Two new private async helper functions (using existing `git_output` / `git_check` from `zbobr_utility`):

```rust
async fn capture_git_head(dir: &Path) -> String {
    // git rev-parse HEAD
    // returns empty string on error (non-git dir)
}

async fn collect_agent_commits(dir: &Path, baseline: &str) -> Vec<String> {
    if baseline.is_empty() { return Vec::new(); }
    // git log --first-parent --format=%h <baseline>..HEAD
    // --first-parent: excludes user commits merged from origin/<work_branch>
    //   because those arrive as second parents of finalization merge commits
}
```

**3b.** Per-iteration baseline capture: inside the retry loop, immediately after the `StageContext` push block (~line 560), before `start_mcp_server`:
```rust
let commit_baseline = capture_git_head(&work_dir).await;
```

**3c.** Retry-path capture (before `continue` at ~line 670):
```rust
let agent_commits = collect_agent_commits(&work_dir, &commit_baseline).await;
let role_session = self.zbobr.role_session(self.task_id);
role_session.modify_task(move |mut task| {
    if let Some(stage) = task.context.stages.last_mut() {
        stage.commits = agent_commits;
    }
    task
}).await.unwrap_or_else(|e| tracing::warn!("Failed to record commits: {e}"));
continue;
```

**3d.** Final-path capture: restructure the `finalize_stage_session` call (~line 681):
```rust
// Bind result before checking — must capture commits for ALL finalization outcomes
let finalize_result = self.zbobr.finalize_stage_session(
    self.task_id, self.pipeline, self.stage, &work_dir, outcome, last_mapped_tool,
).await?;

// Capture AFTER finalization (includes merge commits from update_worktree).
// --first-parent ensures user commits merged from origin/<work_branch> are excluded.
let all_commits = collect_agent_commits(&work_dir, &commit_baseline).await;
let role_session = self.zbobr.role_session(self.task_id);
role_session.modify_task(move |mut task| {
    if let Some(stage) = task.context.stages.last_mut() {
        stage.commits = all_commits;
    }
    task
}).await.unwrap_or_else(|e| tracing::warn!("Failed to record commits: {e}"));

if let Some(e) = finalize_result {
    server_handle.abort();
    return Err(e);
}
server_handle.abort();
return Ok(());
```

### 4. Reviewer prompt — `zbobr/src/init.rs`

Update step 5 in `REVIEWER_PROMPT` (around line 921):

Old: "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user according to the git history."

New: "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user. Commits listed under a stage's `Commits:` field in the task context are known agent and system commits (including finalization merge commits); any commit not listed there was likely introduced by the user."

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext` |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL` const; `commits` field in `MdStage`; Display output; `MdStage::from_str` parse; `MdContext::from_str` parse; `from_stage_context`/`into_stage_context` mapping; prompt-mode inclusion fix |
| `zbobr-dispatcher/src/cli.rs` | `capture_git_head` + `collect_agent_commits` helpers; `commit_baseline` per iteration; retry capture before `continue`; restructured final-path capture after `finalize_stage_session` for ALL outcomes |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` step 5 |

---

## Verification

1. `cargo build` — no compile errors.
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Roundtrip: `StageContext` with commits → serialize to markdown → parse back → equal commits.
   - Backward compat: empty commits produces no `Commits:` line; parsing existing markdown without `Commits:` gives empty commits.
   - Prompt inclusion: stage with commits but no records is NOT skipped in prompt mode.
3. Manual integration check: run a task stage, verify context markdown contains `Commits:` with correct SHAs including finalization merge commits but excluding user commits from remote.

---

## Key Design Decisions

**Why `--first-parent`?**
Cleanly solves the user-commit problem without explicit SHA tracking. During `update_worktree()`, user commits arrive as second parents of merge commits. First-parent traversal follows only the local-branch chain, so merge commits (M1, M2 — system-created) appear but their merged-in user commits (U1) don't. This is a standard git idiom for "commits that landed on this branch" vs "commits that were brought in via merge."

**Why restructure `finalize_stage_session` call?**
The `Ok(Some(e))` path (execution error) still runs `perform_stash_and_push`, so commits exist after that path. The early-return pattern `if let Some(e) = ...` is idiomatic Rust but placed the capture point incorrectly. Binding the result first and capturing unconditionally is the minimal structural fix.

**Why per-iteration baseline (not per-stage)?**
Each retry creates its own `StageContext` entry. The baseline must scope to each attempt's start so that retry N's commits are attributed to retry N's context entry, not mixed with other attempts.

**Why capture both in retry path AND final path?**
Retry path hits `continue` before `finalize_stage_session` — without a pre-`continue` capture, those commits are permanently lost. Final path must capture AFTER `finalize_stage_session` to include merge commits created during finalization.

**`COMMITS_LABEL` const** (project rule 1: no repeated string literals): the label is used in both Display and parse paths.

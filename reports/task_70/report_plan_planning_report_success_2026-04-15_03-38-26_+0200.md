# Plan: Show Commits in Context (Issue #314) — v10

## Context

Reviewers need to distinguish between commits made by the agent during a stage and commits introduced externally (user pushes to the work branch). This plan adds `commits: Vec<String>` to `StageContext` so each stage records its short commit SHAs in the rendered context, and updates the reviewer prompt to use that information.

Previous plans (v9/ctx_rec_15) were rejected (ctx_rec_16) because commit capture was placed immediately after `execute_tool()`, BEFORE `finalize_stage_session()` runs. The finalization path calls `perform_stash_and_push → update_worktree` which can create additional merge commits (remote work branch merge + base branch merge). Those commits would be absent from `stage.commits`, breaking attribution.

**This plan (v10) fixes this by using two capture points:**
1. **Retry path** (before `continue`): capture `baseline..HEAD` to record agent commits from a failed attempt that will retry. This is necessary because `finalize_stage_session()` is skipped on retry.
2. **Final path** (after `finalize_stage_session()`): capture `baseline..HEAD` to record ALL commits — agent commits AND finalization merge commits — in one shot. Since author rewriting also happens inside `finalize_stage_session`, this also captures final post-rewrite SHAs.

---

## Architecture

### 1. Domain model — `zbobr-api/src/task.rs`

Add `commits: Vec<String>` to `StageContext`:

```rust
pub struct StageContext {
    pub info: StageInfo,
    pub records: Vec<ContextRecord>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub commits: Vec<String>,
}
```

Update the `StageContext { ... }` construction site in `zbobr-dispatcher/src/cli.rs` (line ~545) to include `commits: Vec::new()`.

### 2. Markdown serialization — `zbobr-api/src/context/mod.rs`

**2a.** Add `commits: Vec<String>` to `MdStage` struct (line ~363).

**2b.** `MdStage` Display: after the records loop, if `commits` is non-empty, emit:
```
  Commits: `abc1234` `def5678`
```
Use a `const COMMITS_LABEL: &str = "Commits"` at module level to prevent label divergence. Emit in both prompt and non-prompt modes.

**2c.** `MdContext::from_str` parse path (line ~550): add detection for the `Commits:` line between the `MdRecord::try_parse` check and the `"- "` stage-title check. Parse backtick-wrapped tokens into `stage.commits`. This is the ONLY real parse path — `MdStage::from_str` is not called during context deserialization.

**2d.** `MdStage::from_stage_context` (line ~446): add `commits: stage.commits.clone()`.

**2e.** `MdStage::into_stage_context` (line ~486): add `commits: self.commits`.

**2f.** Prompt-mode inclusion fix in `MdContext::from_task_context` (line ~651):
- Old: `if for_prompt && md_stage.records.is_empty() { continue; }`
- New: `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }`

### 3. Commit capture — `zbobr-dispatcher/src/cli.rs`

#### 3a. Two new private async helpers (use existing `git_output` from `zbobr_utility`)

```rust
async fn capture_git_head(dir: &Path) -> String {
    git_output(dir, &["rev-parse", "HEAD"]).await.unwrap_or_default()
}

async fn collect_agent_commits(dir: &Path, baseline: &str) -> Vec<String> {
    if baseline.is_empty() { return Vec::new(); }
    let range = format!("{}..HEAD", baseline);
    match git_output(dir, &["log", "--format=%h", &range]).await {
        Ok(out) if !out.is_empty() => out.lines().map(str::to_string).collect(),
        _ => Vec::new(),
    }
}
```

#### 3b. Per-iteration baseline capture

At the **start of each retry-loop iteration**, immediately after the `StageContext` push block (after line ~560, before `start_mcp_server`):

```rust
let commit_baseline = capture_git_head(&work_dir).await;
```

#### 3c. Retry-path capture (before `continue`)

Inside `if outcome.execution_failed { ... if attempts_remaining > 0 { ... continue; } }`, just before the `continue` at line ~670:

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

#### 3d. Final-path capture (after `finalize_stage_session`)

After `finalize_stage_session()` returns successfully (after line ~695, before `server_handle.abort()`):

```rust
let all_commits = collect_agent_commits(&work_dir, &commit_baseline).await;
let role_session = self.zbobr.role_session(self.task_id);
role_session.modify_task(move |mut task| {
    if let Some(stage) = task.context.stages.last_mut() {
        stage.commits = all_commits;
    }
    task
}).await.unwrap_or_else(|e| tracing::warn!("Failed to record commits: {e}"));
```

Note: If `finalize_stage_session()` returns `Ok(Some(e))` (error path with early return), commit capture is skipped — acceptable since the stage failed anyway.

#### 3e. Retry path semantics (correctness check)

- Iteration N: baseline_N captured → execute_tool() → agent creates commits → capture `baseline_N..HEAD` → `continue`
- Iteration N+1: baseline_N+1 = HEAD (which is `post_execute_N`) → execute_tool() → captures only NEW commits from attempt N+1
- Final iteration: captures `baseline_final..HEAD` AFTER finalization — includes both agent commits and merge commits

#### 3f. Author-rewrite correctness

With `overwrite_author = true`, author rewriting happens inside `finalize_stage_session → perform_stash_and_push → update_worktree`. Capturing AFTER `finalize_stage_session` returns means we get the FINAL rewritten SHAs, not pre-rewrite ones. This is better than v9 which had the pre-rewrite SHA limitation.

### 4. Reviewer prompt — `zbobr/src/init.rs`

Update step 5 in `REVIEWER_PROMPT` (around line 921):

Old: "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user according to the git history."

New: "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user. Commits listed under a stage's `Commits:` field in the task context are known agent and system commits (including finalization merges); commits not listed there are likely user commits."

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext`; update construction site |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL` const; `commits` field in `MdStage`; serialize in Display; parse in `MdContext::from_str`; mapping in `from_stage_context`/`into_stage_context`; fix prompt-mode inclusion check |
| `zbobr-dispatcher/src/cli.rs` | `capture_git_head` and `collect_agent_commits` helpers; `commit_baseline` per iteration; retry-path capture before `continue`; final-path capture after `finalize_stage_session()` |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` step 5 |

---

## Verification

1. `cargo build` — no compile errors.
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Roundtrip: `StageContext` with `commits` → serialize to markdown → parse back → equal commits.
   - Backward compat: empty `commits` produces no `Commits:` line; existing markdown without `Commits:` parses with empty commits.
   - Prompt inclusion: stage with commits but no records is NOT skipped in prompt mode.
3. Manual integration check: run a task stage, verify the resulting context markdown contains a `Commits:` line with the correct short SHAs including any merge commits from finalization.

---

## Key Design Decisions

**Why two capture points instead of one?**
- Retried failed attempts skip `finalize_stage_session()` entirely (they hit `continue`). Without a capture before `continue`, those commits would be permanently lost.
- The final attempt must capture AFTER `finalize_stage_session()` to include merge commits from `update_worktree`.

**Why `baseline..HEAD` (not `origin/branch..HEAD`)?**
- The baseline is captured at the start of each retry iteration, so it's always precisely "what existed before this attempt started" — not an approximation based on remote state.
- Using `origin/branch..HEAD` would conflate commits from multiple attempts.

**Why not append commits across retry attempts?**
- Each retry creates a NEW `StageContext` entry. Commits are attributed per entry, so each stage context accurately shows what that specific attempt did.

**Why is error-path commit capture acceptable to skip?**
- When `finalize_stage_session()` returns an error, the task is in a failed state. Reviewer attribution is moot — the priority is understanding the failure, not commit attribution.

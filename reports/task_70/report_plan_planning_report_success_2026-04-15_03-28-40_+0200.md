# Plan: Show Commits in Context (Issue #314) — v9

## Context

Reviewers need to distinguish between commits made by the agent during a stage and commits pushed by the user via GitHub. This plan adds per-attempt commit attribution to `StageContext`.

Previous versions (v8/ctx_rec_13) were blocked because commit collection was placed only inside `finalize_stage_session()`, which is **never called** for retried failed attempts (`continue` at line 670). `execution_failed = true` can result from an agent that actually ran (`exit_ok: false`) and may have created commits before exiting non-zero. The fix: collect commits **immediately after `execute_tool()` returns**, before any outcome branch.

Code-confirmed facts:
- `execution_failed = true` covers both `Err(...)` (provider couldn't start) and `exit_ok: false` (agent ran, output captured, committed possible changes)
- On `execution_failed && attempts_remaining > 0`, code hits `continue` at line 670, skipping `finalize_stage_session()` entirely
- No git cleanup (reset/clean/stash) happens between retries — commits from a failed attempt persist in `work_dir`

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

Update the `StageContext { ... }` push site (line ~545-561 in `zbobr-dispatcher/src/cli.rs`) to include `commits: Vec::new()`.

---

### 2. Markdown serialization — `zbobr-api/src/context/mod.rs`

**2a.** Add `commits: Vec<String>` to `MdStage` struct (line ~363).

**2b.** `MdStage::Display` (line ~370): after records loop, if `commits` is non-empty emit:
```
  Commits: `abc1234` `def5678`
```
Use a `const COMMITS_LABEL: &str = "Commits"` at module level to prevent label divergence. Emit in both prompt and non-prompt mode.

**2c.** `MdContext::from_str` parse path (line ~550): add detection between the `MdRecord::try_parse` check and the `"- "` stage-title check. Parse backtick-wrapped tokens into `stage.commits`. This is the ONLY real parse path — `MdStage::from_str` is not called during context deserialization.

**2d.** `MdStage::from_stage_context` (line ~446): add `commits: stage.commits.clone()`.

**2e.** `MdStage::into_stage_context` (line ~486): add `commits: self.commits`.

**2f.** Prompt-mode inclusion fix in `MdContext::from_task_context` (line ~651):
- Old: `if for_prompt && md_stage.records.is_empty() { continue; }`
- New: `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }`

---

### 3. Commit capture — `zbobr-dispatcher/src/cli.rs`

#### Key architectural decision

Commit collection happens **immediately after `execute_tool()` returns** (before the `if outcome.execution_failed` branch at line ~649). This ensures commits are captured for ALL attempts — successful, failed-with-retry, and failed-exhausted.

#### 3a. Two new private async helpers

```rust
async fn capture_git_head(dir: &Path) -> String {
    git_output(dir, &["rev-parse", "HEAD"]).await.unwrap_or_default()
}

async fn collect_agent_commits(dir: &Path, baseline: &str) -> Vec<String> {
    if baseline.is_empty() {
        return Vec::new();
    }
    let range = format!("{}..HEAD", baseline);
    match git_output(dir, &["log", "--format=%h", &range]).await {
        Ok(out) if !out.is_empty() => out.lines().map(|s| s.to_string()).collect(),
        _ => Vec::new(),
    }
}
```

Using existing `git_output` from `zbobr_utility` (already imported at line ~20).

#### 3b. Per-attempt baseline capture

At the **start of each retry-loop iteration**, BEFORE `execute_tool()` runs (right after the `StageContext` push block, before line ~598):

```rust
let commit_baseline = capture_git_head(&work_dir).await;
```

#### 3c. Immediate commit collection after each attempt

AFTER `execute_tool()` returns, BEFORE `if outcome.execution_failed` (between lines ~611 and ~649). Store `role_session` from line ~544 for reuse here:

```rust
let agent_commits = collect_agent_commits(&work_dir, &commit_baseline).await;
role_session
    .modify_task(move |mut task| {
        if let Some(stage) = task.context.stages.last_mut() {
            stage.commits = agent_commits;
        }
        task
    })
    .await
    .unwrap_or_else(|e| tracing::warn!("Failed to record commits: {e}"));
```

#### 3d. No changes to `finalize_stage_session`

Commits are recorded before any branching — no new parameters needed.

#### 3e. Retry path semantics

When `execution_failed && attempts_remaining > 0`:
- commits ARE recorded before reaching `continue` — correct even if agent ran and committed
- on the next iteration, fresh baseline is captured AFTER those commits are already in HEAD
- next attempt's range `<post-failed-HEAD>..HEAD` correctly captures only NEW commits from the retry

#### 3f. Author-rewrite note

Commits captured before `finalize_stage_session` → before `rewrite_authors_on_worktree`. With `overwrite_author = false` (default), SHAs are stable. With `overwrite_author = true`, pre-rewrite SHAs recorded — acknowledged limitation in reviewer prompt language.

---

### 4. Reviewer prompt — `zbobr/src/init.rs`

Update step 5 in `REVIEWER_PROMPT` (around line 921):

Old: "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user according to the git history."

New: "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user. Commits listed under a stage's `Commits:` field in the task context are known agent commits; commits not listed there are likely user commits (attribution may be incomplete for stages where commit tracking was unavailable or where author rewriting was enabled)."

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext`; update all construction sites |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL` const; `commits` field in `MdStage`; serialize in `Display`; parse in `MdContext::from_str`; mapping in `from_stage_context`/`into_stage_context`; fix prompt-mode inclusion check |
| `zbobr-dispatcher/src/cli.rs` | `capture_git_head` and `collect_agent_commits` helpers; capture baseline per-loop-iteration; collect+record commits immediately after `execute_tool()` before any outcome branch; store `role_session` for reuse |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` step 5 |

---

## Verification

1. `cargo build` — no compile errors.
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Roundtrip: `StageContext` with `commits` → serialize to markdown → parse back → equal commits.
   - Backward compat: empty `commits` produces no `Commits:` line; existing markdown without `Commits:` parses with empty commits.
   - Prompt inclusion: stage with commits and no records is NOT skipped in prompt mode.
3. Manual integration check: run a task stage, verify the resulting context markdown contains a `Commits:` line with correct short SHAs.

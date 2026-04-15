# Plan v13: Show Commits in Context (Issue #314)

## Context

The feature stores per-stage agent commits in `StageContext.commits` so reviewers can distinguish agent commits from user commits. Plans v11–v12 established the model and markdown serialization approach. Two blocking gaps remain (ctx_rec_23):

1. **Gap 1 — `task overwrite-author` CLI command**: Plan v12 renamed `dest_branch` to `baseline_commit` in `rewrite_authors_on_worktree` but left the CLI caller's behavior undefined.
2. **Gap 2 — Retry path commit rewriting**: Failed provider retries don't call `perform_stash_and_push`, so per-attempt baseline approach leaves failed-attempt commits unrewritten when `overwrite_author=true`.

Secondary concern: `capture_git_head` returning `""` on error is an unsafe sentinel.

---

## Core Design Decisions

### Gap 1: Parameter rename, not new function

Rename `dest_branch: &str` → `lower_bound: &str` in `rewrite_authors_on_worktree`. This generalizes the parameter to accept either a branch name or a commit SHA.

- **CLI command** (`zbobr/src/commands.rs`): continues to pass `dest_branch` as `lower_bound` — behavior is **unchanged** (still rewrites `dest_branch..HEAD`).
- **Dispatcher** (`zbobr-dispatcher/src/cli.rs`): passes `stage_baseline` SHA as `lower_bound` — rewrites only the current stage's commits.

No second function or split API needed.

### Gap 2: Single `stage_baseline` before the retry loop; no per-attempt commit capture

- Capture `stage_baseline` **once** before the provider retry loop (not per iteration).
- On the **retry path** (provider failed, `continue`): do **not** capture commits. Failed-attempt `StageContext` entries keep `commits: Vec::new()`. This is the "explicit model change" option from the reviewer.
- On the **final path** (after `finalize_stage_session`): capture `collect_agent_commits(&work_dir, &stage_baseline)` and store in `stages.last_mut().commits`.
- Pass `stage_baseline` (not a per-attempt baseline) to `finalize_stage_session` → `perform_stash_and_push` → `rewrite_authors_on_worktree`. This ensures **all** commits from all provider attempts (A1, A2 from attempt 1 and B1, B2 from attempt 2) are rewritten in one pass.

This is consistent with the user requirement: "determine stage commits → rewrite them → store them to the stage record." The stage commits are determined from `stage_baseline..HEAD` after finalization.

### Secondary concern: explicit error handling for `capture_git_head`

`capture_git_head` returns `anyhow::Result<String>`. On error, log a warning and set `stage_baseline = String::new()`. `collect_agent_commits` skips git log when baseline is empty and returns `Vec::new()`.

---

## Architecture Plan

### 1. Domain model — `zbobr-api/src/task.rs`

Add `commits: Vec<String>` to `StageContext`:
```
#[serde(default, skip_serializing_if = "Vec::is_empty")]
pub commits: Vec<String>,
```
Update `StageContext { ... }` construction in `zbobr-dispatcher/src/cli.rs` (~line 550) to include `commits: Vec::new()`.

### 2. Utility function — `zbobr-utility/src/lib.rs` (~line 327)

Rename parameter `dest_branch: &str` → `lower_bound: &str` in `rewrite_authors_on_worktree`. Update `git filter-branch` command range from `'<dest_branch>'..HEAD` to `'<lower_bound>'..HEAD`. Update doc comment.

### 3. Markdown serialization — `zbobr-api/src/context/mod.rs`

- **3a.** Add `const COMMITS_LABEL: &str = "Commits"` at module level.
- **3b.** Add `commits: Vec<String>` to `MdStage` struct.
- **3c.** `MdStage::from_stage_context` (~line 446): add `commits: stage.commits.clone()`.
- **3d.** `MdStage::into_stage_context` (~line 486): add `commits: self.commits`.
- **3e.** `MdStage` Display: after the records loop, if `commits` is non-empty, emit `  Commits: \`abc1234\` \`def5678\`` (two-space indent, backtick-wrapped SHAs).
- **3f.** `MdStage::from_str` (~line 403): detect `trimmed.starts_with(COMMITS_LABEL)` and parse backtick-wrapped tokens into `commits`.
- **3g.** `MdContext::from_str` (~line 547): detect `COMMITS_LABEL` line, parse backtick-wrapped tokens into current stage's `commits`.
- **3h.** Prompt-mode skip fix in `MdContext::from_task_context` (~line 651):
  - Old: `if for_prompt && md_stage.records.is_empty() { continue; }`
  - New: `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }`

### 4. Commit capture and wiring — `zbobr-dispatcher/src/cli.rs`

**4a.** Two new private async helpers (using existing `git_output` from `zbobr_utility`):

```
async fn capture_git_head(dir: &Path) -> anyhow::Result<String>
    // git rev-parse HEAD; return Ok(trimmed sha) or Err

async fn collect_agent_commits(dir: &Path, baseline: &str) -> Vec<String>
    // if baseline.is_empty() { return Vec::new() }
    // git log --first-parent --format=%h <baseline>..HEAD
    // on error: warn and return Vec::new()
```

**4b.** `perform_stash_and_push`: add `stage_baseline: &str` parameter. Pass `stage_baseline` as `lower_bound` to `rewrite_authors_on_worktree` instead of `&base_branch`.

**4c.** `finalize_stage_session`: add `stage_baseline: &str` parameter. Thread through to all three `perform_stash_and_push` calls (interruption path, error path, success path).

**4d.** Stage execution site (before the provider retry loop, ~line 525): capture baseline once:
```rust
let stage_baseline = capture_git_head(&work_dir).await
    .unwrap_or_else(|e| {
        tracing::warn!("Failed to capture git HEAD for stage commit baseline: {e}");
        String::new()
    });
```

**4e.** Retry path (`execution_failed && continue`, ~line 670): **no commit capture**. Leave retry-attempt `StageContext.commits` empty. Just `continue`.

**4f.** Final path — restructure the `finalize_stage_session` call (after line 681):
```rust
let finalize_result = self.zbobr.finalize_stage_session(
    self.task_id, self.pipeline, self.stage, &work_dir, outcome, last_mapped_tool,
    &stage_baseline,
).await?;

// Capture AFTER finalization (includes finalization merge commits from update_worktree).
// --first-parent excludes user commits merged as second parents of merge commits.
let all_commits = collect_agent_commits(&work_dir, &stage_baseline).await;
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

### 5. CLI command caller — `zbobr/src/commands.rs` (~line 660)

Update `rewrite_authors_on_worktree` call to pass `dest_branch` as the renamed `lower_bound` parameter. Behavior is unchanged; only the function signature changed.

### 6. Reviewer prompt — `zbobr/src/init.rs`

Update REVIEWER_PROMPT step 5: commits listed under a stage's `Commits:` field are known agent and system commits (including finalization merge commits); any commit not listed there was likely introduced by the user and should be accepted.

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext` |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL` const; `commits` in `MdStage`; Display; from_str parse; `from/into_stage_context` mapping; prompt-mode skip fix |
| `zbobr-utility/src/lib.rs` | Rename `dest_branch` → `lower_bound` in `rewrite_authors_on_worktree` |
| `zbobr-dispatcher/src/cli.rs` | `capture_git_head` + `collect_agent_commits` helpers; `stage_baseline` before retry loop; `stage_baseline` param chain through `finalize_stage_session` → `perform_stash_and_push`; restructured final-path capture |
| `zbobr/src/commands.rs` | Update call site to match renamed parameter |
| `zbobr/src/init.rs` | Update REVIEWER_PROMPT step 5 |

---

## Rationale for Key Choices

**Why rename parameter rather than split the function?**
The utility is identical — only the lower bound differs by use case. Caller convention (branch name vs SHA) is an input concern, not a behavioral one.

**Why single `stage_baseline` before the retry loop?**
- Ensures ALL commits from all provider attempts are rewritten with `overwrite_author=true` (using `stage_baseline..HEAD` in `rewrite_authors_on_worktree`).
- Ensures the baseline SHA is the exclusive lower bound of the rewrite range and is therefore never rewritten — `git log stage_baseline..HEAD` remains valid after the rewrite.

**Why no commit capture on retry path?**
The reviewer requirement is attribution per *stage outcome*, not per *provider attempt*. Failed provider retries are implementation noise. The last `StageContext` entry (from the final execution) gets all commits from `stage_baseline..HEAD`, covering all attempts holistically.

**Why capture AFTER `finalize_stage_session`?**
`finalize_stage_session` calls `perform_stash_and_push` which calls `update_worktree` (creating merge commits M1, M2). These system merge commits must appear in `Commits:`. Capturing before finalization would miss them.

**Why `--first-parent` in `collect_agent_commits`?**
User insight: "all stage commits are always local and any user commits may come only on merging." `update_worktree` merges user commits as second parents of M1, M2. `--first-parent` follows only the local-branch chain: [A1, A2, M1, M2], excluding user commits (second parents of M1/M2).

---

## Verification

1. `cargo build` — no compile errors.
2. Grep all callers of `rewrite_authors_on_worktree` — ensure both call sites compile with renamed parameter.
3. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Roundtrip: `StageContext` with commits → markdown → parse back → equal.
   - Backward compat: empty commits → no `Commits:` line; parsing markdown without `Commits:` → empty commits.
   - Prompt inclusion: stage with commits but no records is NOT skipped in prompt mode.
4. Integration check with `overwrite_author=true`: verify all stage commits (across retries if applicable) are rewritten; verify `Commits:` in context markdown contains correct post-rewrite SHAs; verify `git log stage_baseline..HEAD` matches.

# Plan v12: Show Commits in Context (Issue #314)

## Context

The feature records agent/system commits in `StageContext.commits` so reviewers can distinguish agent commits from user commits. Plans v1–v11 established the domain model and markdown serialization approach. The final blocker (ctx_rec_20) was that `rewrite_authors_on_worktree` uses `dest_branch..HEAD` as the filter-branch range — this rewrites the per-stage baseline commit SHA, making `baseline..HEAD` queries unstable after rewriting.

New user requirement: `rewrite_authors_on_worktree` must be applied **only to commits detected as agent commits**, not all commits since the destination branch. Algorithm:
1. Determine stage commits
2. Rewrite them if necessary
3. Store them in the stage record

## Core Insight: Baseline-Anchored Range

Change the filter-branch range from `dest_branch..HEAD` to `commit_baseline..HEAD`:

- `commit_baseline` = `git rev-parse HEAD` captured at the START of each stage iteration
- `commit_baseline` is the **boundary** of the rewrite range — it is never itself rewritten
- After rewriting, `git log --first-parent commit_baseline..HEAD` still works and returns exactly the current-stage commits

User insight: "all stage commits are always local and any user commits may come only on merging."
- Before `update_worktree()`: all local commits are agent commits
- After `update_worktree()`: user commits arrive as second parents of merge commits M1, M2
- `--first-parent` gives [A1, A2, M1, M2] (agent+system), excludes user commits (second parents)

## Architecture Plan

### 1. Domain model — `zbobr-api/src/task.rs`

Add `commits: Vec<String>` to `StageContext` (alongside `records`):
```
#[serde(default, skip_serializing_if = "Vec::is_empty")]
pub commits: Vec<String>,
```
Update the `StageContext { ... }` construction in `zbobr-dispatcher/src/cli.rs` (~line 550) to include `commits: Vec::new()`.

### 2. Markdown serialization — `zbobr-api/src/context/mod.rs`

**2a.** Add `const COMMITS_LABEL: &str = "Commits"`.

**2b.** Add `commits: Vec<String>` to `MdStage` struct.

**2c.** `MdStage::from_stage_context` (~line 446): add `commits: stage.commits.clone()`.

**2d.** `MdStage::into_stage_context` (~line 486): add `commits: self.commits`.

**2e.** `MdStage` Display: after the records loop, if `commits` is non-empty, emit:
```
  Commits: `abc1234` `def5678`
```

**2f.** `MdStage::from_str` (~line 403): detect `trimmed.starts_with(COMMITS_LABEL)` and parse backtick-wrapped tokens into `commits`.

**2g.** `MdContext::from_str` (~line 547): detect `COMMITS_LABEL` line, parse backtick-wrapped tokens into current stage's `commits`.

**2h.** Prompt-mode skip fix in `MdContext::from_task_context` (~line 651):
- Old: `if for_prompt && md_stage.records.is_empty() { continue; }`
- New: `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }`

### 3. `rewrite_authors_on_worktree` — `zbobr-utility/src/lib.rs` (~line 321)

Change `dest_branch: &str` → `baseline_commit: &str`. Update the `git filter-branch` range from `'<dest_branch>'..HEAD` to `'<baseline_commit>'..HEAD`. Update doc comment.

### 4. Commit capture and wiring — `zbobr-dispatcher/src/cli.rs`

**4a.** Two new helpers:
```rust
async fn capture_git_head(dir: &Path) -> String { /* git rev-parse HEAD; "" on error */ }
async fn collect_agent_commits(dir: &Path, baseline: &str) -> Vec<String> {
    // git log --first-parent --format=%h <baseline>..HEAD
}
```

**4b.** `perform_stash_and_push`: add `commit_baseline: &str`. Pass it to `rewrite_authors_on_worktree` instead of `&base_branch`.

**4c.** `finalize_stage_session`: add `commit_baseline: &str`. Pass through to all three `perform_stash_and_push` calls.

**4d.** Stage loop — capture baseline after StageContext push (~line 561):
```rust
let commit_baseline = capture_git_head(&work_dir).await;
```

**4e.** Retry path — before `continue` (~line 670): capture and store commits in `stages.last_mut()`.

**4f.** Final path — restructure `finalize_stage_session` call: bind result first, capture commits for ALL outcomes, then check `if let Some(e) = finalize_result`:
```rust
let finalize_result = self.zbobr.finalize_stage_session(..., &commit_baseline).await?;
let all_commits = collect_agent_commits(&work_dir, &commit_baseline).await;
// store in stages.last_mut().commits
if let Some(e) = finalize_result { server_handle.abort(); return Err(e); }
```

### 5. Reviewer prompt — `zbobr/src/init.rs`

Update REVIEWER_PROMPT step 5: commits under `Commits:` are known agent/system commits; anything not listed was likely introduced by the user.

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext` |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL`; `commits` in `MdStage`; Display; parse; `from/into_stage_context`; prompt-mode fix |
| `zbobr-utility/src/lib.rs` | `dest_branch` → `baseline_commit` in `rewrite_authors_on_worktree` |
| `zbobr-dispatcher/src/cli.rs` | helpers; baseline capture; commit_baseline param chain; retry capture; restructured final-path capture |
| `zbobr/src/init.rs` | Update REVIEWER_PROMPT |

## Key Design Decisions

**Why `commit_baseline..HEAD` not `dest_branch..HEAD` for rewriting?**
The baseline is the exclusive lower bound of the rewrite range, so it is never modified. All subsequent queries `commit_baseline..HEAD` work before and after rewriting. The previous `dest_branch..HEAD` approach rewrote the baseline itself (P → P'), invalidating any saved SHA.

**Why this correctly scopes to agent commits only?**
`commit_baseline` is captured before execution. All commits between baseline and HEAD are agent-created (before `update_worktree` merges) or system merge commits (M1, M2). User commits are second parents of M1/M2 and excluded by `--first-parent`.

**Why capture AFTER `finalize_stage_session` (not inside)?**
One capture point covers all three finalization outcomes. Binding result before capture and before `if let Some(e)` ensures commits are recorded on the error path too.

**Why per-iteration baseline?**
Each retry has its own `StageContext` entry. Baseline scopes attribution to each attempt.

## Verification

1. `cargo build` — no compile errors.
2. Unit tests in `zbobr-api/src/context/mod.rs`: roundtrip with commits; backward compat (no `Commits:` line when empty); prompt inclusion when commits non-empty.
3. Grep all callers of `rewrite_authors_on_worktree` — ensure all pass `commit_baseline` correctly.
4. Integration: run stage with `overwrite_author=true`; verify `Commits:` in context markdown; verify `git log commit_baseline..HEAD` matches.

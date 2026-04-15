# Plan v24: Show Commits in Context (Issue #314)

## Context

Issue #314 requires recording per-stage agent commits in `StageContext` so that:
1. Reviewer prompts can show which commits were made by agents vs. users.
2. The `overwrite_author` command rewrites only agent-made commits, not user commits.

Plans v11–v23 converged on the core architecture. Plan v24 resolves both blocking issues identified in plan_review_adversarial (ctx_rec_46) that remain from v23.

---

## Blocking Issues Fixed in v24 (relative to v23)

### Fix 1: `MdContext::from_str` state machine must handle `Commits:` lines

**Problem (ctx_rec_46, issue 1):** Plan v23 mentions updating `MdStage::from_str`, but the active parser for persisted context is the line-by-line `MdContext::from_str` state machine in `zbobr-api/src/context/mod.rs:547-621`. Any line not matching `<!-- stage -->`, a record, or a stage-title causes `bail!("Unrecognized line in context: ...")` at line 610. If serialization emits `Commits:` lines but the parser doesn't handle them, reading any context with stored commits will crash.

**Fix:** In `MdContext::from_str`, before the `bail!` at line 610, insert:
- If `trimmed.starts_with("Commits:")` and `current_stage.is_some()`:
  - Extract backtick-wrapped tokens from the rest of the line
  - Extend `current_stage.commits` with them
  - `continue` (skip bail)

This must be explicitly implemented; no other parser path covers this case.

### Fix 2: Post-second-sync commits must be collected after the second `update_worktree`

**Problem (ctx_rec_46, issue 2):** After `rewrite_authors_on_worktree`, `git filter-branch` rewrites local SHAs so they diverge from the remote. The second `update_worktree` call (line 2183) runs `git merge origin/<work_branch>` in Phase 8, which creates a new merge commit when the remote tip is not an ancestor of the rewritten local HEAD. Plan v23 stores commits before this second `update_worktree`, so that new merge commit is never recorded.

**Fix:** After the second `update_worktree` completes, collect any new merge commits using the top of the pre-second-sync state as the lower bound:
- `post_sync_new = collect_merge_commits(work_dir, &final_commits[0])` — `final_commits[0]` is the rewritten HEAD before the second sync; any merge commit created by the second sync will appear above it
- `all_final = post_sync_new + final_commits` (newest first)
- `store_commits_to_task(all_final)` — non-fatal

If the second sync creates no merge commit (remote was already an ancestor after rewrite), `post_sync_new` is empty and `all_final == final_commits` — correct in both cases.

---

## Full Implementation Plan

### 1. Domain model — `zbobr-api/src/task.rs`

Add to `StageContext`:
```rust
#[serde(default, skip_serializing_if = "Vec::is_empty")]
pub commits: Vec<String>,
```
Update all `StageContext { ... }` construction sites to include `commits: Vec::new()`.

### 2. Utility functions — `zbobr-utility/src/lib.rs`

**Add `check_worktree_presence`:**
- Runs `git rev-parse --is-inside-work-tree` with stdout+stderr captured.
- Returns `Ok(true)` on success.
- Returns `Ok(false)` only when stderr contains "not a git repository".
- Returns `Err(...)` for any other non-zero exit.

**Add `capture_git_head`:**
- Runs `git rev-parse HEAD`, returns trimmed full SHA (internal bookmark only — never stored).

**Add `collect_agent_commits`:**
- Runs `git log --first-parent --format=%.12H <lower_bound>..HEAD` (12-char abbreviated).
- Returns empty `Vec` if `lower_bound` is empty.

**Add `collect_merge_commits`:**
- Runs `git log --first-parent --merges --format=%.12H <lower_bound>..HEAD` (12-char abbreviated).
- Returns empty `Vec` if `lower_bound` is empty.

**Update `rewrite_authors_on_worktree` signature:**
```rust
pub async fn rewrite_authors_on_worktree(
    work_dir: &Path,
    lower_bound: &str,       // filter-branch scope: <lower_bound>..HEAD
    commits: &[String],      // 12-char abbreviated SHAs — only these get rewritten
    git_user_name: &str,
    git_user_email: &str,
) -> Result<()>
```
- If `commits.is_empty()` → return `Ok(())` immediately.
- `--env-filter` script uses shell `for` + `case` prefix matching against `commits`.

### 3. Markdown serialization — `zbobr-api/src/context/mod.rs`

**`MdStage` struct** (lines 363–367): add `commits: Vec<String>` field.

**`MdStage::from_stage_context`** (lines 444–483): add `commits: stage.commits.clone()` to the returned `MdStage`.

**`MdStage::into_stage_context`** (lines 486–495): add `commits: self.commits` to the returned `StageContext`.

**`MdStage::fmt (Display)`** (lines 369–400): after emitting all records, if `commits` is non-empty, emit:
```
  Commits: `<abbrev1>` `<abbrev2>` ...
```
(2-space indent). Applies in both persist-mode and prompt-mode (abbreviated SHAs are the same in both).

**`MdContext::from_str` state machine** (lines 547–621): before `bail!` at line 610, insert:
```
if trimmed.starts_with("Commits:") {
    if let Some(stage) = current_stage.as_mut() {
        // extract backtick-wrapped tokens from trimmed["Commits:".len()..]
        stage.commits.extend(parsed_tokens);
        continue;
    }
}
bail!("Unrecognized line in context: {}", trimmed);
```

**Prompt-mode stage skip condition**: a stage with commits but no records is NOT skipped (include in prompt).

### 4. Core logic — `zbobr-dispatcher/src/cli.rs`

#### `perform_stash_and_push` — full revised sequence

New parameter: `commit_baseline: &str` (passed from `finalize_stage_session`).

1. Replace `.is_ok()` check with `check_worktree_presence(work_dir).await?`.
2. Stash (existing logic, gated on `is_git_repo`).
3. **Pre-sync collection**: `pre_commits = collect_agent_commits(work_dir, commit_baseline)` (fatal).
4. Record `pre_update_head = capture_git_head(work_dir)` (internal bookmark, not stored).
5. First `update_worktree`.
6. **Post-sync collection**: `sync_commits = collect_merge_commits(work_dir, &pre_update_head)` (fatal). Store `dedup(pre_commits + sync_commits)` via `store_commits_to_task` (non-fatal, warn-and-continue).
7. If `overwrite_author && is_uptodate && is_git_repo && !pre_commits.is_empty()`:
   a. `rewrite_authors_on_worktree(work_dir, commit_baseline, &pre_commits, ...)` — fatal.
   b. **Count-based post-rewrite re-collection**:
      ```
      N = pre_commits.len(); M = sync_commits.len()
      all = collect_agent_commits(work_dir, commit_baseline) — fatal
      ff_count = all.len().saturating_sub(N + M)
      final_commits = all.into_iter().skip(ff_count).collect()
      ```
   c. Second `update_worktree` — fatal on conflict.
   d. **Post-second-sync collection** (v24 fix for issue 2):
      ```
      post_sync_new = collect_merge_commits(work_dir, &final_commits[0]) — fatal
      all_final = post_sync_new + final_commits
      store_commits_to_task(all_final) — non-fatal
      ```

#### `store_commits_to_task` (new non-fatal helper)

Modifies `task.context.stages.last_mut().commits`; logs warning on failure, does not propagate error.

#### `finalize_stage_session`

Add `commit_baseline: &str` parameter; thread through to all `perform_stash_and_push` call sites.

#### `CliStageRunner::run` — per-attempt baseline capture

Before `execute_tool` in each attempt: capture `attempt_baseline = capture_git_head(&work_dir)`.

Retry path (before `continue`): collect `pre_commits`, optionally rewrite + re-collect using `attempt_baseline`, store via `store_commits_to_task`.

Thread `attempt_baseline` to `finalize_stage_session`.

### 5. CLI command — `zbobr/src/commands.rs`

`overwrite_author`: replace range-based commit collection with stored commits:
```rust
let agent_commits: Vec<String> = task.context.stages.iter()
    .flat_map(|s| s.commits.iter().cloned())
    .collect::<std::collections::HashSet<_>>()
    .into_iter().collect();
```
Pass to updated `rewrite_authors_on_worktree`.

**Dry-run output** (lines 679–694): update to show `agent_commits` from stored context, so the dry-run reflects the same commit set that will actually be rewritten.

### 6. Reviewer prompt — `zbobr/src/init.rs`

Add guidance to `REVIEWER_PROMPT` explaining that commits listed under each stage were made by the agent, and commits not listed are user contributions.

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext` |
| `zbobr-api/src/context/mod.rs` | Add `commits` to `MdStage`; update Display, from_stage_context, into_stage_context; fix `MdContext::from_str` state machine to handle `Commits:` lines |
| `zbobr-utility/src/lib.rs` | Add 4 new functions; update `rewrite_authors_on_worktree` signature |
| `zbobr-dispatcher/src/cli.rs` | Rewrite `perform_stash_and_push` with count-based + post-second-sync collection |
| `zbobr/src/commands.rs` | Use stored commits in `overwrite_author`; update dry-run output |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` |

---

## Verification

1. `cargo build` — verify all changed function signatures compile.
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Round-trip: context with `Commits:` line serializes and parses correctly.
   - Missing `Commits:` line parses to `commits: []`.
   - Stage with commits but no records not skipped in prompt-mode.
   - `MdContext::from_str` does NOT bail on valid `Commits:` lines.
3. Unit test: `rewrite_authors_on_worktree` with empty `commits` → `Ok(())`, no git invocation.
4. Unit tests: `check_worktree_presence` for git/non-git/error cases.
5. Unit test: `collect_merge_commits` excludes single-parent commits.
6. Verify count-based logic for both ff and merge cases with N pre-commits, M sync-commits.
7. Verify post-second-sync collection: if `final_commits[0]` is already HEAD after second sync (no new merge), `post_sync_new` is empty.

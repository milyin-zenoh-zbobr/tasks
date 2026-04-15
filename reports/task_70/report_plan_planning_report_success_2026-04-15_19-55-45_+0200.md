# Plan v21: Show Commits in Context (Issue #314)

## Context

Issue #314 requires recording per-stage agent commits in `StageContext` so that:
1. Reviewer prompts can classify which commits were made by agents vs. users.
2. The `overwrite_author` command applies only to agent-made commits, not user commits.

Plans v11–v20 converged on the core architecture. Plan v20 was blocked by two issues (ctx_rec_39):
1. Finalization drops post-sync merge commits when `overwrite_author` is false: pre-sync commit list is stored but never updated after `update_worktree` creates merge commits, so those system-generated commits are absent from the stage record and look like user commits to reviewers.
2. `overwrite_author` CLI command recomputes agent commits via `collect_agent_commits(&repo_dir, dest_branch)` — a fresh heuristic — instead of using the exact SHAs already recorded in `task.context.stages[*].commits`.

Plan v21 resolves both gaps while preserving all other v20 decisions.

---

## Key Design Decisions

All decisions from v20 are preserved. Two additions:

**Why re-collect after first `update_worktree` even when not rewriting?**
`update_worktree` (github.rs:860-878) merges the remote work branch and possibly the base branch, creating merge commits whose SHAs are not in `pre_commits`. From a reviewer's perspective, these are system/infrastructure commits (not user commits) and must appear in the stored list. Without re-collection, those merge commits are invisible to the reviewer classification logic.

**Why use recorded `StageContext.commits` for the `overwrite_author` command?**
The task already loads its snapshot at commands.rs:615-619 with full `task.context.stages` data. Using a fresh `dest_branch..HEAD` heuristic can capture human commits pushed directly on the work branch, violating the user's explicit requirement: "rewrite_authors_on_worktree should be applied only to commits detected as made by the agent." Using the union of already-stored `commits` fields is the exact set determined by the stage-ownership mechanism.

---

## Changes

### 1. Domain model — `zbobr-api/src/task.rs`

Add to `StageContext`:
```rust
#[serde(default, skip_serializing_if = "Vec::is_empty")]
pub commits: Vec<String>,
```
Update all `StageContext { ... }` construction sites to include `commits: Vec::new()`.

### 2. Utility functions — `zbobr-utility/src/lib.rs`

**Add `check_worktree_presence`** (new — NOT a wrapper around `git_check`):
- Runs `git rev-parse --is-inside-work-tree` capturing stdout+stderr.
- Returns `Ok(true)` on success.
- Returns `Ok(false)` only when stderr contains "not a git repository" (expected on first run).
- Returns `Err(...)` for any other non-zero exit (corrupt repo, permissions, spawn failure).
- This replaces the existing `is_git_repo` check that uses `git_output(...).is_ok()`, which swallows unexpected errors.

**Add `capture_git_head`**:
- Runs `git rev-parse HEAD`, returns the SHA string.

**Add `collect_agent_commits`**:
- Runs `git log --first-parent --format=%H <lower_bound>..HEAD`.
- Returns the list of SHAs. Returns empty Vec if `lower_bound` is empty.

**Update `rewrite_authors_on_worktree` signature**:
```rust
pub async fn rewrite_authors_on_worktree(
    work_dir: &Path,
    lower_bound: &str,       // range lower bound for filter-branch traversal scope
    commits: &[String],      // exact full SHAs to rewrite
    git_user_name: &str,
    git_user_email: &str,
) -> Result<()>
```
- If `commits.is_empty()` → return `Ok(())` immediately.
- Build range `<lower_bound>..HEAD` for `filter-branch` scope.
- The `--env-filter` script only rewrites commits whose `$GIT_COMMIT` is in the `commits` slice:
  ```sh
  AGENT_COMMITS="<sha1> <sha2> ..."
  case " $AGENT_COMMITS " in
    *" $GIT_COMMIT "*) export GIT_AUTHOR_NAME="..."; export GIT_AUTHOR_EMAIL="...";
                       export GIT_COMMITTER_NAME="..."; export GIT_COMMITTER_EMAIL="...";;
  esac
  ```

### 3. Markdown serialization — `zbobr-api/src/context/mod.rs`

- Add `const COMMITS_LABEL: &str = "Commits"`.
- Add `commits: Vec<String>` to `MdStage` struct.
- `MdStage::from_stage_context`: `commits: stage.commits.clone()`.
- `MdStage::into_stage_context`: `commits: self.commits`.
- **Persist path**: emit full SHAs (backtick-wrapped), e.g. `` Commits: `<sha1>` `<sha2>` `` when non-empty.
- **Prompt-mode rendering**: emit abbreviated SHAs (first 12 chars) for readability.
- `from_str` / parsing: detect `COMMITS_LABEL` lines, parse backtick-wrapped tokens as commit SHAs.
- Prompt-mode stage-skip condition: `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }`.

### 4. Core logic — `zbobr-dispatcher/src/cli.rs`

#### `perform_stash_and_push` (return type stays `anyhow::Result<()>`)

New signature (add `commit_baseline: &str`):
```rust
async fn perform_stash_and_push(
    self: &Arc<Self>,
    task_id: u64,
    work_dir: &Path,
    role: &str,
    pipeline_name: &Pipeline,
    commit_baseline: &str,
) -> anyhow::Result<()>
```

Revised sequence:

1. **Replace `git_output(...).is_ok()` check** with `zbobr_utility::check_worktree_presence(work_dir).await?`.

2. **Early commit collection (before first `update_worktree`)**:
   ```
   pre_commits = collect_agent_commits(work_dir, commit_baseline)  // warn-and-continue on error
   store_commits_to_task(self, task_id, pre_commits.clone())       // non-fatal, immediate
   ```

3. **First `update_worktree`** call (existing).

4. **[NEW in v21] Post-sync re-collection** — after first `update_worktree` succeeds:
   ```
   post_sync_commits = collect_agent_commits(work_dir, commit_baseline)  // warn-and-continue
   store_commits_to_task(self, task_id, post_sync_commits.clone())       // non-fatal, overwrites
   ```
   Captures merge commits created by `update_worktree` that are absent from `pre_commits`.

5. **Author rewrite** (if `overwrite_author && is_uptodate && is_git_repo && !pre_commits.is_empty()`):
   - `rewrite_authors_on_worktree(work_dir, commit_baseline, &pre_commits, ...)` — fatal (`?`).
     Uses `pre_commits` (NOT `post_sync_commits`): only agent-authored commits need rewriting; merge commits from `update_worktree` are already correctly authored.
   - Re-collect: `post_commits = collect_agent_commits(work_dir, commit_baseline).await?` — fatal.
   - `store_commits_to_task(self, task_id, post_commits)` — non-fatal, overwrites again.
   - Second `update_worktree` (existing).

#### `store_commits_to_task` (new non-fatal helper method)

```rust
async fn store_commits_to_task(self: &Arc<Self>, task_id: u64, commits: Vec<String>) {
    if let Err(e) = self.task_session(task_id).modify_task(move |mut task| {
        if let Some(stage) = task.context.stages.last_mut() {
            stage.commits = commits;
        }
        task
    }).await {
        tracing::warn!("Failed to store commits for task #{task_id}: {e}");
    }
}
```

#### `finalize_stage_session` (add `commit_baseline: &str` parameter)

Pass `commit_baseline` through to all three `perform_stash_and_push` call sites. Per-path error semantics unchanged from v20.

#### `CliStageRunner::run` — per-attempt baseline capture

Inside the provider retry loop, just before `execute_tool`:
```rust
let is_git_repo = zbobr_utility::check_worktree_presence(&work_dir).await?;
let attempt_baseline = if is_git_repo {
    zbobr_utility::capture_git_head(&work_dir).await?
} else {
    String::new()
};
```

**Retry path** (before `continue`):
```
pre_commits = collect_agent_commits(&work_dir, &attempt_baseline)  // warn-and-continue
final_commits = if overwrite_author && !pre_commits.is_empty() {
    rewrite_authors_on_worktree(..., &pre_commits, ...)  // warn-and-continue on retry path
    re-collect post-rewrite                              // warn-and-continue
} else {
    pre_commits
}
store_retry_commits(&role_session, final_commits)  // non-fatal
```

`store_retry_commits`: non-fatal helper analogous to `store_commits_to_task` but takes `TaskSession`.

Thread `attempt_baseline` through to `finalize_stage_session` call.

### 5. CLI command — `zbobr/src/commands.rs`

Update `overwrite_author` — **[KEY v21 CHANGE]**:

Replace `collect_agent_commits(&repo_dir, dest_branch)` with:
```rust
let agent_commits: Vec<String> = {
    let mut seen = std::collections::HashSet::new();
    task.context.stages.iter()
        .flat_map(|s| s.commits.iter().cloned())
        .filter(|c| seen.insert(c.clone()))
        .collect()
};
if agent_commits.is_empty() {
    println!("No recorded agent commits found in task; nothing to rewrite.");
    return Ok(());
}
```

The rest is unchanged: `dest_branch` is still passed as `lower_bound` to `rewrite_authors_on_worktree` (scopes filter-branch traversal); env-filter only rewrites commits in `agent_commits`.

In dry-run path: show only commits in `agent_commits`.

### 6. Reviewer prompt — `zbobr/src/init.rs`

Add guidance to `REVIEWER_PROMPT`:

> When classifying commits as agent vs user: commits whose full hashes appear in ANY `Commits:` field anywhere in the task context (across all stages and all retry attempts) are known agent and system commits. Commits absent from ALL such lists are likely user-introduced and should be accepted as-is without questioning them.

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext`; update construction sites |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL`; `commits` in `MdStage`; full SHAs in persist, abbreviated in prompt-only; from_str; from/into_stage_context; prompt-mode skip fix |
| `zbobr-utility/src/lib.rs` | Add `check_worktree_presence`; add `capture_git_head`; add `collect_agent_commits`; update `rewrite_authors_on_worktree` with `commits: &[String]` param |
| `zbobr-dispatcher/src/cli.rs` | `perform_stash_and_push`: add `commit_baseline`, early collect+store, **post-sync re-collect+store**, rewrite with `pre_commits`, post-rewrite re-collect+store; `store_commits_to_task` helper; `finalize_stage_session`: add `commit_baseline` param; `CliStageRunner::run`: per-attempt baseline, retry-path collect/rewrite/store |
| `zbobr/src/commands.rs` | `overwrite_author`: **use recorded `StageContext.commits` union instead of fresh heuristic** |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` |

---

## Verification

1. `cargo build` — verify all changed function signatures compile.
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Round-trip: `StageContext` with full SHAs → serialized markdown → parsed → equal.
   - Backward compat: no `Commits:` line parses to empty `commits`.
   - Prompt rendering: abbreviated SHAs shown; stage with commits but no records is NOT skipped.
3. Unit test for `rewrite_authors_on_worktree`: empty `commits` slice → returns `Ok(())` without running git.
4. Unit tests for `check_worktree_presence`: git repo → `Ok(true)`; non-git dir → `Ok(false)`; unexpected error → `Err`.
5. All `StageContext { ... }` construction sites include `commits: Vec::new()`.

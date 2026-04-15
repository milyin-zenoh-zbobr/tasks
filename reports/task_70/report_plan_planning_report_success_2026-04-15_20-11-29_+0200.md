# Plan v22: Show Commits in Context (Issue #314)

## Context

Issue #314 requires recording per-stage agent commits in `StageContext` so that:
1. Reviewer prompts can classify which commits were made by agents vs. users.
2. The `overwrite_author` command applies only to agent-made commits, not user commits.

Plans v11–v21 converged on the core architecture. Plan v21 was blocked by two issues (ctx_rec_41):
1. **Post-sync `baseline..HEAD` recollection marks external commits as stage-owned.** When `update_worktree` fast-forwards (no local diverge), `git log baseline..HEAD` after the update includes remote commits that were NOT created by this stage. Those commits are stored as stage-owned, violating the requirement that `overwrite_author` must not touch commits from other authors.
2. **Prompt-mode hash contract is inconsistent.** Plan v21 renders abbreviated SHAs (12 chars) in prompt-mode but the reviewer prompt guidance referenced "full hashes." These are contradictory — the reviewer sees abbreviated SHAs in the prompt.

Plan v22 resolves both issues while preserving all other v21 decisions.

---

## Key Design Decisions (v22 Additions)

**Why targeted merge-commit collection instead of post-sync `baseline..HEAD` re-collection?**

`update_worktree` calls `merge_ref_into_worktree`, which uses `git merge --no-edit`. If the local branch is behind the remote (no diverging local commits), git fast-forwards HEAD to the remote tip — no new commit is created, but `baseline..HEAD` now includes the remote's commits. Re-collecting from `baseline` after the sync would falsely attribute those imported commits to this stage.

The correct approach: record HEAD *before* calling `update_worktree`, then after it completes collect only the commits that are *both* new (in `pre_update_head..HEAD`) and are actual merge commits (`--merges`). Merge commits (2+ parents) are created by an actual `git merge`; fast-forwarded commits have only 1 parent and are excluded. This guarantees only system-created merge commits from the sync operation enter the stored list.

**Why abbreviated SHAs in prompt-mode with matching reviewer guidance?**

The issue requests human-readable commit display. Abbreviated 12-char SHAs satisfy this. The reviewer prompt must be updated to instruct agents to match by prefix, not exact 40-char hash. This is the only consistent choice given abbreviated prompt-mode rendering.

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

**Add `check_worktree_presence`**:
- Runs `git rev-parse --is-inside-work-tree` with stdout+stderr captured.
- Returns `Ok(true)` on success.
- Returns `Ok(false)` only when stderr contains "not a git repository".
- Returns `Err(...)` for any other non-zero exit (unexpected git errors, permissions, spawn failure).
- Replaces the existing `git_output(...).is_ok()` pattern in `perform_stash_and_push`, which silently swallows unexpected errors.

**Add `capture_git_head`**:
- Runs `git rev-parse HEAD`, returns the trimmed SHA string.

**Add `collect_agent_commits`**:
- Runs `git log --first-parent --format=%H <lower_bound>..HEAD`.
- Returns the list of SHAs. Returns empty `Vec` if `lower_bound` is empty.

**Add `collect_merge_commits`** ← **NEW in v22**:
- Runs `git log --first-parent --merges --format=%H <lower_bound>..HEAD`.
- Returns only commits that are actual merge commits (2+ parents).
- Returns empty `Vec` if `lower_bound` is empty.
- Used exclusively for collecting sync-created merge commits after `update_worktree`.

**Update `rewrite_authors_on_worktree` signature**:
```rust
pub async fn rewrite_authors_on_worktree(
    work_dir: &Path,
    lower_bound: &str,       // range lower bound for filter-branch traversal scope
    commits: &[String],      // exact full SHAs to rewrite (only these are touched)
    git_user_name: &str,
    git_user_email: &str,
) -> Result<()>
```
- If `commits.is_empty()` → return `Ok(())` immediately, no git operation.
- Build range `<lower_bound>..HEAD` for `filter-branch` scope.
- The `--env-filter` script only rewrites commits whose `$GIT_COMMIT` is in the `commits` slice:
  ```sh
  AGENT_COMMITS="<sha1> <sha2> ..."
  case " $AGENT_COMMITS " in
    *" $GIT_COMMIT "*) export GIT_AUTHOR_NAME="..."; export GIT_AUTHOR_EMAIL="...";;
  esac
  ```

### 3. Markdown serialization — `zbobr-api/src/context/mod.rs`

- Add `const COMMITS_LABEL: &str = "Commits"`.
- Add `commits: Vec<String>` to `MdStage` struct.
- `MdStage::from_stage_context`: `commits: stage.commits.clone()`.
- `MdStage::into_stage_context`: `commits: self.commits`.
- **Persist path**: emit full SHAs (backtick-wrapped), e.g. `` Commits: `<sha1>` `<sha2>` `` when non-empty.
- **Prompt-mode rendering**: emit first 12 chars of each SHA (abbreviated), e.g. `` Commits: `<abbrev1>` `<abbrev2>` ``.
- `from_str` / parsing: detect `COMMITS_LABEL` lines, parse backtick-wrapped tokens as commit SHAs.
- Prompt-mode stage-skip condition: stage with commits but no records is **NOT** skipped (existing skip only triggers when both records and commits are empty).

### 4. Core logic — `zbobr-dispatcher/src/cli.rs`

#### `perform_stash_and_push` — revised sequence

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

Sequence:

1. **Replace `git_output(...).is_ok()` check** with `zbobr_utility::check_worktree_presence(work_dir).await?`.

2. **Stash** (existing logic, gated on `is_git_repo`).

3. **Pre-sync commit collection** (before `update_worktree`):
   ```
   pre_commits = collect_agent_commits(work_dir, commit_baseline)  // warn-and-continue on error
   store_commits_to_task(self, task_id, pre_commits.clone())       // non-fatal, immediate
   ```

4. **Record pre-update HEAD** ← **NEW in v22**:
   ```
   pre_update_head = if is_git_repo {
       capture_git_head(work_dir).await.unwrap_or_default()   // warn-and-continue
   } else { String::new() }
   ```

5. **First `update_worktree`** call (existing).

6. **Post-sync merge-commit collection** ← **REPLACES v21's blind post-sync recollection**:
   ```
   sync_commits = collect_merge_commits(work_dir, &pre_update_head)  // warn-and-continue
   combined_commits = [pre_commits, sync_commits].concat().dedup()
   store_commits_to_task(self, task_id, combined_commits.clone())    // non-fatal, overwrites
   ```
   - `collect_merge_commits` uses `--merges` filter → only actual merge commits, never fast-forwarded external commits.
   - If `update_worktree` fast-forwarded: `sync_commits` is empty; stored list = `pre_commits`.

7. **Author rewrite** (if `overwrite_author && is_uptodate && is_git_repo && !pre_commits.is_empty()`):
   - `rewrite_authors_on_worktree(work_dir, commit_baseline, &pre_commits, ...)` — fatal (`?`).
     Uses `pre_commits` (NOT `combined_commits`): only agent-authored commits need rewriting; merge commits from the sync are already correctly authored.
   - Re-collect after rewrite:
     ```
     post_rewrite_commits = collect_agent_commits(work_dir, commit_baseline).await?   // fatal
     sync_commits2 = collect_merge_commits(work_dir, &pre_update_head).await?         // fatal
     final_commits = [post_rewrite_commits, sync_commits2].concat().dedup()
     store_commits_to_task(self, task_id, final_commits)   // non-fatal
     ```
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

Pass `commit_baseline` through to all three `perform_stash_and_push` call sites. Per-path error semantics unchanged from v21.

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
pre_commits = collect_agent_commits(&work_dir, &attempt_baseline)     // warn-and-continue
final_commits = if overwrite_author && !pre_commits.is_empty() {
    rewrite_authors_on_worktree(&work_dir, &attempt_baseline, &pre_commits, ...)  // warn-and-continue
    re-collect post-rewrite (collect_agent_commits)                               // warn-and-continue
} else {
    pre_commits
}
// No update_worktree on retry path — no merge commits to collect
store_retry_commits(&role_session, final_commits)  // non-fatal
```

Note: on retry path there is no `update_worktree`, so `collect_merge_commits` is not needed — only agent commits matter.

`store_retry_commits`: non-fatal helper analogous to `store_commits_to_task` but takes `TaskSession` and `task_id`.

Thread `attempt_baseline` through to `finalize_stage_session` call.

### 5. CLI command — `zbobr/src/commands.rs`

Update `overwrite_author`:

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

`dest_branch` is still passed as `lower_bound` to `rewrite_authors_on_worktree` (scopes filter-branch traversal scope); the env-filter only rewrites commits in `agent_commits`.

In dry-run path: show only commits in `agent_commits`.

### 6. Reviewer prompt — `zbobr/src/init.rs`

Add guidance to `REVIEWER_PROMPT` ← **UPDATED in v22 to use abbreviated-hash contract**:

> When classifying commits as agent vs user: commits whose abbreviated SHA (first 12 characters) appears in ANY `Commits:` field anywhere in the task context (across all stages and all retry attempts) are known agent and system commits. To match: a commit is agent-owned if its full SHA starts with any such 12-char prefix. Commits absent from ALL such lists are likely user-introduced and should be accepted as-is without questioning them.

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext`; update all construction sites |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL`; `commits` in `MdStage`; full SHAs in persist-mode, 12-char abbreviated in prompt-mode; from_str; from/into_stage_context; prompt-mode skip fix |
| `zbobr-utility/src/lib.rs` | Add `check_worktree_presence`; add `capture_git_head`; add `collect_agent_commits`; **add `collect_merge_commits`**; update `rewrite_authors_on_worktree` with `commits: &[String]` param |
| `zbobr-dispatcher/src/cli.rs` | `perform_stash_and_push`: add `commit_baseline`, pre-sync collect+store, **record `pre_update_head`**, **post-sync merge-commit-only collection+store**, rewrite with `pre_commits`, post-rewrite re-collect+store; `store_commits_to_task` helper; `finalize_stage_session`: add `commit_baseline` param; `CliStageRunner::run`: per-attempt baseline, retry-path collect/rewrite/store |
| `zbobr/src/commands.rs` | `overwrite_author`: use recorded `StageContext.commits` union instead of fresh heuristic |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` with abbreviated-hash contract |

---

## Verification

1. `cargo build` — verify all changed function signatures compile.
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Round-trip: `StageContext` with full SHAs → serialized markdown → parsed → equal (full SHAs preserved).
   - Prompt-mode rendering: abbreviated 12-char SHAs shown (not full SHAs).
   - Backward compat: no `Commits:` line parses to empty `commits`.
   - Stage with commits but no records is NOT skipped in prompt-mode.
3. Unit test for `rewrite_authors_on_worktree`: empty `commits` slice → returns `Ok(())` without running git.
4. Unit tests for `check_worktree_presence`: git repo → `Ok(true)`; non-git dir → `Ok(false)`; unexpected error → `Err`.
5. Unit test for `collect_merge_commits`: only merge commits (2+ parents) appear in result, regular commits from fast-forward do not.
6. All `StageContext { ... }` construction sites include `commits: Vec::new()`.

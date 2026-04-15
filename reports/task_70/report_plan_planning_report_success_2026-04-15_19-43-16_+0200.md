# Plan v20: Show Commits in Context (Issue #314)

## Context

Issue #314 requires recording per-stage agent commits in `StageContext` so that:
1. Later reviewer prompts can classify which commits were made by agents vs. users.
2. The `overwrite_author` author-rewriting command applies only to agent-made commits, not user commits.

Plans v11–v19 converged on the core architecture. Plan v19 was blocked by two design issues (ctx_rec_37):
1. `check_is_git_repo` using `git_check` still collapses all non-zero git exits to `Ok(false)`, conflating "expected no-repo on first run" with unexpected git failures.
2. Commit metadata is dropped when `perform_stash_and_push` fails (stash/sync/push failure loses all stored commits), defeating the ownership-tracking goal.

Plan v20 resolves both blocking issues while preserving all other v19 decisions.

---

## Key Design Decisions

**Why `check_worktree_presence` instead of `git_check`?**
`git_check` (zbobr-utility/src/lib.rs:218) returns `Ok(false)` for ALL non-zero git exits — including broken repos, permission errors, and "not a git repository". We need to distinguish only the last case (expected on first run) from everything else. The fix: capture stderr and check for the specific "not a git repository" string that git emits, returning `Ok(false)` only then and `Err(...)` for other non-zero exits. This is a new function, not a wrapper around `git_check`.

**Why `perform_stash_and_push` stores commits internally and returns `anyhow::Result<()>`?**
The plan v19 approach of returning `Vec<String>` and having callers store commits tied metadata storage to push success. The core constraint is that the author rewrite must happen AFTER the first `update_worktree` call (which merges remote state), because rewriting locally before the remote merge would cause SHA conflicts. This means collect+rewrite+re-collect must happen inside `perform_stash_and_push`. The solution: do an EARLY collection of pre-rewrite commits BEFORE the first `update_worktree`, store them immediately (non-fatal), then rewrite+re-collect+overwrite after. Even if the second push fails, commits are already stored.

**Why keep the three separate per-path error semantics from Plan v19?**
Unchanged — the reviewer approved this in ctx_rec_37. Success path: existing fatal behavior preserved. Interrupted/error paths: warn-and-continue on push failure.

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
```rust
pub async fn check_worktree_presence(dir: &Path) -> Result<bool> {
    let output = tokio::process::Command::new("git")
        .args(&["rev-parse", "--is-inside-work-tree"])
        .current_dir(dir)
        .output()   // captures both stdout and stderr
        .await
        .with_context(|| "Failed to spawn: git rev-parse --is-inside-work-tree")?;
    if output.status.success() {
        return Ok(true);
    }
    let stderr = String::from_utf8_lossy(&output.stderr);
    if stderr.contains("not a git repository") {
        return Ok(false);  // expected on first run before agent initializes repo
    }
    anyhow::bail!(
        "git rev-parse --is-inside-work-tree failed unexpectedly in {}: {}",
        dir.display(), stderr.trim()
    )
}
```
Returns:
- `Ok(true)` — confirmed git repo
- `Ok(false)` — confirmed NOT a repo (the specific "not a git repository" message)
- `Err(...)` — unexpected failure (corrupt repo, permission error, spawn failure, other non-zero exit)

**Add `capture_git_head`**:
```rust
pub async fn capture_git_head(dir: &Path) -> Result<String> {
    git_output(dir, &["rev-parse", "HEAD"]).await
}
```

**Add `collect_agent_commits`**:
```rust
pub async fn collect_agent_commits(dir: &Path, lower_bound: &str) -> Result<Vec<String>> {
    if lower_bound.is_empty() {
        return Ok(Vec::new());
    }
    let range = format!("{lower_bound}..HEAD");
    let output = git_output(dir, &["log", "--first-parent", "--format=%H", &range]).await?;
    Ok(output.lines().map(str::to_owned).filter(|s| !s.is_empty()).collect())
}
```

**Update `rewrite_authors_on_worktree` signature** to accept an explicit commit set:
```rust
pub async fn rewrite_authors_on_worktree(
    work_dir: &Path,
    lower_bound: &str,       // range lower bound for filter-branch traversal scope
    commits: &[String],      // exact full SHAs to rewrite (pre-detected, first-parent set)
    git_user_name: &str,
    git_user_email: &str,
) -> Result<()>
```
- If `commits.is_empty()` → return `Ok(())` immediately (no rewrite needed).
- Build range `<lower_bound>..HEAD` for `filter-branch` scope.
- The `--env-filter` shell script checks `$GIT_COMMIT` against the space-separated list of full SHAs. Only matching commits get author/committer overridden. This leaves second-parent (merge) commits from users untouched.
- Env-filter pattern:
  ```sh
  AGENT_COMMITS="<sha1> <sha2> ..."
  case " $AGENT_COMMITS " in
    *" $GIT_COMMIT "*)
      export GIT_AUTHOR_NAME="..."; export GIT_AUTHOR_EMAIL="...";
      export GIT_COMMITTER_NAME="..."; export GIT_COMMITTER_EMAIL="...";;
  esac
  ```

### 3. Markdown serialization — `zbobr-api/src/context/mod.rs`

- Add `const COMMITS_LABEL: &str = "Commits"`.
- Add `commits: Vec<String>` to `MdStage` struct.
- `MdStage::from_stage_context`: `commits: stage.commits.clone()`.
- `MdStage::into_stage_context`: `commits: self.commits`.
- **Persist path** (Display / serialize_context / GitHub backend round-trips): emit full SHAs (backtick-wrapped tokens), e.g. `` Commits: `<sha1>` `<sha2>` `` when non-empty. Full SHAs are required because the env-filter in `rewrite_authors_on_worktree` compares `$GIT_COMMIT` against stored hashes.
- **Prompt-mode rendering**: emit abbreviated SHAs (first 12 chars) for readability. Prompt mode is never reparsed.
- `from_str` / parsing: detect `COMMITS_LABEL` lines, parse backtick-wrapped tokens as commit SHAs.
- Fix prompt-mode stage-skip condition: change to `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }` so stages with commits but no records are included in prompt rendering.

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

Revised body (key changes only):

1. Replace line 2127:
   ```rust
   let is_git_repo = git_output(work_dir, &["rev-parse", "--is-inside-work-tree"])
       .await.is_ok();
   ```
   with:
   ```rust
   let is_git_repo = zbobr_utility::check_worktree_presence(work_dir).await?;
   ```
   Unexpected git failures now propagate via `?` instead of silently producing `false`.

2. **Early commit collection (before first `update_worktree`)**:
   After the stash block and before calling `update_worktree`, add:
   ```rust
   let pre_commits = if is_git_repo && !commit_baseline.is_empty() {
       match zbobr_utility::collect_agent_commits(work_dir, commit_baseline).await {
           Ok(c) => c,
           Err(e) => {
               tracing::warn!("Failed to collect agent commits for task #{task_id}: {e}");
               Vec::new()
           }
       }
   } else {
       Vec::new()
   };
   // Store pre-rewrite commits immediately — decouples metadata from push success
   store_commits_to_task(self, task_id, pre_commits.clone()).await;
   ```

3. Replace the existing `rewrite_authors_on_worktree` call block (lines 2173-2188) with:
   ```rust
   if config.overwrite_author && is_uptodate && is_git_repo && !pre_commits.is_empty() {
       zbobr_utility::rewrite_authors_on_worktree(
           work_dir, commit_baseline, &pre_commits,
           &config.git_user_name, &config.git_user_email,
       ).await?;  // fatal: rewrite is a destructive operation
       // Re-collect post-rewrite SHAs — fatal because rewrite already mutated history
       let post_commits = zbobr_utility::collect_agent_commits(work_dir, commit_baseline).await?;
       // Overwrite stored pre-rewrite SHAs with new post-rewrite SHAs
       store_commits_to_task(self, task_id, post_commits).await;
       // Push rewritten commits
       let is_uptodate = self.update_worktree(&identity).await?;
       if !is_uptodate {
           anyhow::bail!("Merge conflict while pushing rewritten commits for task #{task_id}");
       }
   }
   ```

4. Remove the old `base_branch` variable (previously used as rewrite range); `commit_baseline` replaces it.

**Result**: commits are stored at point 2 (early, before first sync), so even if `update_worktree` fails for a merge conflict, the pre-rewrite commits are already in the task record. If rewrite and second push succeed, stored commits are updated to post-rewrite SHAs.

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

All three `perform_stash_and_push` call sites pass `commit_baseline`. No other changes to finalization control flow — the per-path semantics remain exactly as in Plan v19:
- **Interrupted path**: warn-and-continue on push failure, set_state(pending).
- **Error path**: warn-and-continue on push failure, then existing pause/signal/set_state logic.
- **Success path**: existing fatal behavior exactly preserved on push failure (error log, pause with status and signal, set_state(pending), return Ok(None)).

#### `CliStageRunner::run` — per-attempt baseline capture

Inside the provider retry loop, just before `execute_tool` is called:
```rust
let is_git_repo = zbobr_utility::check_worktree_presence(&work_dir).await?;
let attempt_baseline = if is_git_repo {
    zbobr_utility::capture_git_head(&work_dir).await?
} else {
    String::new()
};
```
- `?` on `check_worktree_presence` propagates unexpected git failures.
- `Ok(false)` (not a repo yet) gracefully yields empty baseline.
- `capture_git_head` failure is fatal (unexpected on a confirmed git repo).

**Retry path** (before `continue`, when `execution_failed`):
```rust
if is_git_repo && !attempt_baseline.is_empty() {
    let pre_commits = match zbobr_utility::collect_agent_commits(&work_dir, &attempt_baseline).await {
        Ok(c) => c,
        Err(e) => { tracing::warn!("...{e}"); Vec::new() }
    };
    let final_commits = if self.zbobr.config().overwrite_author && !pre_commits.is_empty() {
        match zbobr_utility::rewrite_authors_on_worktree(
            &work_dir, &attempt_baseline, &pre_commits,
            &config.git_user_name, &config.git_user_email,
        ).await {
            Ok(()) => {
                zbobr_utility::collect_agent_commits(&work_dir, &attempt_baseline).await
                    .unwrap_or_else(|e| { tracing::warn!("...{e}"); Vec::new() })
            }
            Err(e) => { tracing::warn!("...{e}"); pre_commits }
        }
    } else {
        pre_commits
    };
    store_retry_commits(&role_session, final_commits).await;
}
continue;
```
All retry-path git operations are non-fatal (warn-and-continue) since the stage hasn't finished.

`store_retry_commits` is a non-fatal helper (analogous to `store_commits_to_task` but takes a `TaskSession`):
```rust
async fn store_retry_commits(role_session: &TaskSession, commits: Vec<String>) {
    if let Err(e) = role_session.modify_task(move |mut task| {
        if let Some(stage) = task.context.stages.last_mut() {
            stage.commits = commits;
        }
        task
    }).await {
        tracing::warn!("Failed to store retry commits: {e}");
    }
}
```

**Thread `attempt_baseline` and `is_git_repo` to `finalize_stage_session`**: pass `&attempt_baseline` from its computation site through the call at lines 681–691.

### 5. CLI command — `zbobr/src/commands.rs`

Update `overwrite_author`:
1. After `fetch_refs`, call `zbobr_utility::collect_agent_commits(&repo_dir, dest_branch).await?` to get the first-parent agent commit set.
2. If empty: print "No agent commits detected; nothing to rewrite." and return.
3. In `!dry_run` path: call `rewrite_authors_on_worktree(&repo_dir, dest_branch, &agent_commits, ...)`.
4. In dry-run path: show only commits in `agent_commits`.

### 6. Reviewer prompt — `zbobr/src/init.rs`

Add guidance to `REVIEWER_PROMPT`:

> When classifying commits as agent vs user: commits whose full hashes appear in ANY `Commits:` field anywhere in the task context (across all stages and all retry attempts) are known agent and system commits. Commits absent from ALL such lists are likely user-introduced and should be accepted as-is without questioning them.

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext`; update construction sites |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL`; `commits` in `MdStage`; full SHAs in persist, abbreviated in prompt-only; from_str; from/into_stage_context; prompt-mode skip fix |
| `zbobr-utility/src/lib.rs` | Add `check_worktree_presence` (new, NOT via git_check — inspects stderr); add `capture_git_head`; add `collect_agent_commits`; update `rewrite_authors_on_worktree` with `commits: &[String]` param and conditional env-filter |
| `zbobr-dispatcher/src/cli.rs` | `perform_stash_and_push`: add `commit_baseline`, early collect+store before first `update_worktree`, update rewrite block to pass commit set, stays `-> anyhow::Result<()>`; add `store_commits_to_task` helper; `finalize_stage_session`: add `commit_baseline` param, pass to all three call sites; provider retry loop: `check_worktree_presence` for baseline, retry-path collect/rewrite/store |
| `zbobr/src/commands.rs` | `overwrite_author`: `collect_agent_commits` before rewrite; pass commit set to `rewrite_authors_on_worktree` |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` |

---

## Verification

1. `cargo build` — verify all changed function signatures compile. Key callers: `rewrite_authors_on_worktree` (2 callers), `perform_stash_and_push` (3 call sites in `finalize_stage_session`), `finalize_stage_session` (1 caller in `CliStageRunner::run`).
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Round-trip: `StageContext` with full SHAs → serialized markdown → parsed → equal.
   - Backward compat: no `Commits:` line parses to empty `commits`.
   - Prompt rendering: abbreviated SHAs shown; stage with commits but no records is NOT skipped.
3. Unit test for `rewrite_authors_on_worktree`: empty `commits` slice → returns `Ok(())` without running any git command.
4. Unit test for `check_worktree_presence`:
   - In a real git repo directory → returns `Ok(true)`.
   - In a non-git directory → returns `Ok(false)`.
   - On a path that causes unexpected git error (e.g., unreadable dir) → returns `Err`.
5. All `StageContext { ... }` construction sites include `commits: Vec::new()`.

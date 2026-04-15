# Plan v18: Show Commits in Context (Issue #314)

## Context and Prior Work

Plans v11–v17 established the core architecture:
- `StageContext.commits: Vec<String>` to record per-attempt agent commits
- `git log --first-parent <baseline>..HEAD` as the detection mechanism
- Conditional env-filter in `rewrite_authors_on_worktree` (rewrites only the detected set)
- Per-attempt `attempt_baseline` captured before each provider loop iteration
- Retry-path rewrite failure is fatal
- Both dispatcher and CLI `overwrite-author` command use shared detection utilities in `zbobr-utility`
- Full SHAs in persisted markdown; abbreviated in prompt-only rendering
- Post-rewrite re-collection for accurate stored SHAs

**Plan v17 had two blocking issues (ctx_rec_33):**

1. **All finalization paths**: `finalize_stage_session` calls `perform_stash_and_push` on three paths (interrupted, error, success). Plan v17 only described post-finalization commit storage for the success path. The interruption and error paths would finish without recording commits.

2. **Best-effort degradation still present in correctness-critical spots**: Baseline capture used `unwrap_or_else(|e| { warn!; String::new() })` even on real git worktrees, and post-finalization commit collection (success path) also used warn-and-empty. Both are authoritative for reviewer classification and must be fatal when operating on a real git worktree.

---

## Plan v18: Resolving Both Blocking Issues

### Fix 1: `perform_stash_and_push` Returns Post-Rewrite Commits

Change `perform_stash_and_push` return type from `anyhow::Result<()>` to `anyhow::Result<Vec<String>>`.

Inside `perform_stash_and_push`, after all existing stash/update/rewrite/push logic, add:
- If `is_git_repo && !commit_baseline.is_empty()`:
  - Collect post-rewrite commits: `let commits = zbobr_utility::collect_agent_commits(work_dir, commit_baseline).await?;` (fatal, within `is_git_repo` guard)
  - Return `Ok(commits)`
- Else: return `Ok(Vec::new())`

`finalize_stage_session` receives `commit_baseline: &str` and passes it to `perform_stash_and_push` on **all three paths** (interrupted, error, success). After each call, store the returned commits to the task context using `self.task_session(task_id).modify_task(...)`:

```
interrupted path:
  match perform_stash_and_push(..., commit_baseline).await {
      Ok(commits) => store_commits_to_task(task_id, commits),  // non-fatal
      Err(e) => tracing::warn!("...")  // no commits stored (existing behavior)
  }

error path: same pattern

success path: same pattern (replaces the existing `if let Err(e)` block)
```

`store_commits_to_task` is a small inline helper using `self.task_session(task_id).modify_task`:
```rust
if let Err(e) = self.task_session(task_id).modify_task(move |mut task| {
    if let Some(stage) = task.context.stages.last_mut() {
        stage.commits = commits;
    }
    task
}).await {
    tracing::warn!("Failed to store commits for task #{task_id}: {e}");
}
```
Commit storage itself is non-fatal (stage already finished; this is metadata). The critical fatal point is `collect_agent_commits` inside `perform_stash_and_push`.

### Fix 2: Fatality Rules for Real Git Worktrees

The rule is: if `is_git_repo` is true, git detection failures are fatal. If `is_git_repo` is false (worktree not yet initialized), graceful empty is acceptable.

**Per-attempt baseline capture** (in `CliStageRunner::run`, inside the provider retry loop, before pushing new `StageContext`):

```rust
let is_git_worktree = zbobr_utility::is_git_repo(work_dir).await;
let attempt_baseline = if is_git_worktree {
    zbobr_utility::capture_git_head(work_dir).await?  // fatal on real git worktree
} else {
    String::new()
};
```

This replaces the previous warn-and-empty pattern. `is_git_repo` is a simple helper (`git rev-parse --is-inside-work-tree`, returns `bool`). Since `perform_stash_and_push` already does this check inline, the same logic can be extracted to a shared utility function `zbobr_utility::is_git_repo(dir: &Path) -> bool` (best-effort, returns `false` on error — the check failing is not fatal, only the subsequent git operations are fatal when the check returns true).

**Retry path commit collection** (in `CliStageRunner::run`):

```rust
if !attempt_baseline.is_empty() {
    let pre_commits = zbobr_utility::collect_agent_commits(&work_dir, &attempt_baseline).await?;  // fatal
    if config.overwrite_author && !pre_commits.is_empty() {
        zbobr_utility::rewrite_authors_on_worktree(..., &pre_commits, ...).await?;  // fatal
        let post_commits = zbobr_utility::collect_agent_commits(&work_dir, &attempt_baseline).await?;  // fatal, post-rewrite
        store_stage_commits_on_role_session(&role_session, post_commits).await;
    } else {
        store_stage_commits_on_role_session(&role_session, pre_commits).await;
    }
}
```

`store_stage_commits_on_role_session` is a non-fatal helper using `role_session.modify_task` (same pattern as v17, non-fatal storage).

**Inside `perform_stash_and_push`** (finalization path):

Within the existing `if is_git_repo` gate, `collect_agent_commits` uses `?` (fatal). This is the same `is_git_repo` check already present at line 2127. Pre-rewrite collection, post-rewrite collection, and final commits collection are all fatal when `is_git_repo` is true.

---

## Complete Architecture (all changes)

### 1. Domain model — `zbobr-api/src/task.rs`

Add to `StageContext`:
```rust
#[serde(default, skip_serializing_if = "Vec::is_empty")]
pub commits: Vec<String>,
```
Update all `StageContext { ... }` construction sites to include `commits: Vec::new()`.

### 2. Utility functions — `zbobr-utility/src/lib.rs`

**Add `is_git_repo`** (simple helper, returns `bool`):
```rust
pub async fn is_git_repo(dir: &Path) -> bool
// git rev-parse --is-inside-work-tree
// returns true on Ok, false on Err
```

**Add `capture_git_head`** (returns `Result`):
```rust
pub async fn capture_git_head(dir: &Path) -> Result<String>
// git rev-parse HEAD → trimmed stdout
```

**Add `collect_agent_commits`** (returns `Result`):
```rust
pub async fn collect_agent_commits(dir: &Path, lower_bound: &str) -> Result<Vec<String>>
// guard: lower_bound is empty → Ok(Vec::new())
// git log --first-parent --format=%H <lower_bound>..HEAD
// on error: Err(...)
```

**Update `rewrite_authors_on_worktree` signature** to accept explicit commit set:
```rust
pub async fn rewrite_authors_on_worktree(
    work_dir: &Path,
    lower_bound: &str,       // range lower bound for filter-branch traversal scope
    commits: &[String],      // exact full SHAs to rewrite (from first-parent detection)
    git_user_name: &str,
    git_user_email: &str,
) -> Result<()>
```
- If `commits.is_empty()` → return `Ok(())` (no-op).
- Build `<lower_bound>..HEAD` as the traversal range.
- `--env-filter` shell script checks `$GIT_COMMIT` (always a full 40-char SHA) against the embedded space-separated full SHA list. Author/committer env vars are set only when a match is found.

### 3. Markdown serialization — `zbobr-api/src/context/mod.rs`

- Add `const COMMITS_LABEL: &str = "Commits"`.
- Add `commits: Vec<String>` to `MdStage` struct.
- `MdStage::from_stage_context`: `commits: stage.commits.clone()`.
- `MdStage::into_stage_context`: `commits: self.commits`.
- `MdStage` Display (the persisted serialization path — used by `serialize_context` and GitHub backend round-trips): emit **full SHAs**, e.g. `` Commits: `<full_sha1>` `<full_sha2>` `` when non-empty. No abbreviation, to preserve identity through round-trips.
- Prompt-mode rendering: emit **shortened SHAs** (first 12 chars) for readability. Prompt-mode rendering is never reparsed.
- `from_str` / parsing: detect `COMMITS_LABEL` lines, parse backtick-wrapped tokens as commits. Store as-is (always full SHAs in normal round-trips, so no loss).
- Prompt-mode skip fix: change the stage-skip condition to `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }` so stages with commits but no records are still included in prompt rendering.

### 4. Commit capture and wiring — `zbobr-dispatcher/src/cli.rs`

**`perform_stash_and_push`** signature change:
```rust
async fn perform_stash_and_push(
    self: &Arc<Self>,
    task_id: u64,
    work_dir: &Path,
    role: &str,
    pipeline_name: &Pipeline,
    commit_baseline: &str,   // new parameter
) -> anyhow::Result<Vec<String>>  // changed return type
```

Inside, within the `if is_git_repo` block, after rewrite+push:
```rust
let commits = if !commit_baseline.is_empty() {
    zbobr_utility::collect_agent_commits(work_dir, commit_baseline).await?  // fatal
} else {
    Vec::new()
};
return Ok(commits);
```
Outside the `is_git_repo` guard (no git repo): return `Ok(Vec::new())`.

**`finalize_stage_session`** signature change (add `commit_baseline: &str`). On all three paths, convert existing `if let Err(e) = perform_stash_and_push(...)` to:
```rust
let commits = match self.perform_stash_and_push(task_id, work_dir, role, pipeline, commit_baseline).await {
    Ok(c) => c,
    Err(e) => {
        tracing::warn!("Stash/push failed...: {e}");
        Vec::new()
    }
};
// Store commits (non-fatal)
if let Err(e) = self.task_session(task_id).modify_task(move |mut task| {
    if let Some(stage) = task.context.stages.last_mut() { stage.commits = commits; }
    task
}).await {
    tracing::warn!("Failed to store commits for task #{task_id}: {e}");
}
```

Note: on the success path, the original code fatally returns `Err` if `perform_stash_and_push` returns `Err`. That behavior is **preserved** — only for the interrupted/error paths does the code warn-and-continue. The pattern above uses `Vec::new()` for the warn case, which is consistent with the existing error tolerance on those paths. If collection fails inside `perform_stash_and_push` (on a real git worktree), the `?` makes it return `Err`, so no commits are stored — acceptable on interrupted/error paths, fatal on success path (existing behavior).

**`CliStageRunner::run`** — per-attempt baseline capture (inside provider retry loop, before new `StageContext` push):
```rust
let is_git_worktree = zbobr_utility::is_git_repo(&work_dir).await;
let attempt_baseline = if is_git_worktree {
    zbobr_utility::capture_git_head(&work_dir).await?  // fatal
} else {
    String::new()
};
```

**Retry path** (before `continue`):
```rust
if !attempt_baseline.is_empty() {
    let pre_commits = zbobr_utility::collect_agent_commits(&work_dir, &attempt_baseline).await?;  // fatal
    if config.overwrite_author && !pre_commits.is_empty() {
        zbobr_utility::rewrite_authors_on_worktree(
            &work_dir, &attempt_baseline, &pre_commits,
            &config.git_user_name, &config.git_user_email,
        ).await?;  // fatal
        let post_commits = zbobr_utility::collect_agent_commits(&work_dir, &attempt_baseline).await?;  // fatal, post-rewrite
        store_retry_commits(&role_session, post_commits).await;
    } else {
        store_retry_commits(&role_session, pre_commits).await;
    }
}
continue;
```
Where `store_retry_commits` is a non-fatal helper calling `role_session.modify_task` to set `stage.commits` on the last stage.

**`finalize_stage_session` caller** (line 681–691): pass `&attempt_baseline` as the new parameter.

**Update all three `perform_stash_and_push` call sites** in `finalize_stage_session` to pass `commit_baseline`.

### 5. CLI command — `zbobr/src/commands.rs`

Update `overwrite_author`:
1. After `fetch_refs`, call `zbobr_utility::collect_agent_commits(&repo_dir, dest_branch).await?` to get the first-parent agent commit set.
2. If empty: print "No agent commits detected; nothing to rewrite." and return.
3. In `!dry_run` path: call `rewrite_authors_on_worktree(&repo_dir, dest_branch, &agent_commits, ...)`.
4. In dry-run path: use `--first-parent` in the git log invocation to show only what would actually be rewritten.

### 6. Reviewer prompt — `zbobr/src/init.rs`

Add guidance to `REVIEWER_PROMPT`:

> When classifying commits as agent vs user: commits whose full hashes appear in ANY `Commits:` field anywhere in the task context (across all stages and all retry attempts) are known agent and system commits. Commits absent from ALL such lists are likely user-introduced and should be accepted as-is without questioning them.

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext`; update construction sites |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL`; `commits` in `MdStage`; Display: full SHAs in persist path, abbreviated in prompt-only; from_str; from/into_stage_context; prompt-mode skip fix |
| `zbobr-utility/src/lib.rs` | Add `is_git_repo`, `capture_git_head`, `collect_agent_commits` (returns `Result`); update `rewrite_authors_on_worktree` signature with `commits: &[String]` and conditional env-filter |
| `zbobr-dispatcher/src/cli.rs` | `perform_stash_and_push`: add `commit_baseline` param, change return to `Vec<String>`, collect commits inside; `finalize_stage_session`: add `commit_baseline` param, store returned commits on ALL three paths; provider retry loop: add `is_git_repo` check + fatal `capture_git_head`; retry path: fatal `collect_agent_commits`, optional rewrite with post-rewrite re-collection; thread `attempt_baseline` through to `finalize_stage_session` |
| `zbobr/src/commands.rs` | `overwrite_author`: `collect_agent_commits` before rewrite; pass set to `rewrite_authors_on_worktree`; dry-run log uses `--first-parent` |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` |

---

## Key Design Decisions

**Why `perform_stash_and_push` returns `Vec<String>`?**
It is the only function that knows both `is_git_repo` (already determined inline at line 2127) and `commit_baseline`. Having it collect and return post-rewrite commits is the cleanest way to ensure all three finalization paths (interrupted, error, success) in `finalize_stage_session` get the commits without duplicating the collection logic.

**Why `is_git_repo` gate before baseline capture?**
The comment at line 2125 says "The work_dir may not yet be a git repo on the first run". Failing fatally in that case would prevent first-run execution. The `is_git_repo` check (returns `bool`, best-effort false on error) gates the fatal path: only when confirmed as a real git worktree do we treat `capture_git_head` failure as fatal.

**Why `collect_agent_commits` returns `Result` and uses `?` inside `is_git_repo` guards?**
This function is now correctness-critical: it defines the rewrite boundary (pre-commits) and the reviewer's commit classification (stored post-commits). Silent empty-set fallback would silently skip rewriting or produce empty commit records, violating the feature's contract. Fatal behavior when confirmed on a real git worktree makes failures visible.

**Why full SHAs in persisted markdown?**
The task GitHub backend persists context as markdown (via `serialize_context`) and re-parses it (via `parse_context`). Abbreviated hashes in normal serialization would permanently lose SHA identity on the first round-trip, breaking the `$GIT_COMMIT` comparison in the env-filter. Full SHAs in normal serialization; abbreviation only in prompt-mode rendering (never reparsed).

**Why conditional env-filter in `rewrite_authors_on_worktree`?**
`--first-parent` is a traversal constraint, not expressible as a plain revision range. `filter-branch` visits all commits in `<baseline>..HEAD`, but the env-filter script only rewrites commits in the pre-collected set. Second-parent user commits in the same range are visited but NOT rewritten.

**Why post-rewrite re-collection?**
`git filter-branch` rewrites commit objects; their SHAs change. Storing pre-rewrite SHAs makes the stage record invalid after rewriting. Re-collecting from the same `attempt_baseline` with `--first-parent` after rewrite returns the actual live SHAs.

**Why `collect_agent_commits` and `capture_git_head` and `is_git_repo` in `zbobr-utility`?**
Both the dispatcher (`zbobr-dispatcher`) and the CLI command (`zbobr`) need these. Centralizing in `zbobr-utility` (a shared dependency of both) prevents divergent implementations.

**Why store commits on retry path even when `overwrite_author` is false?**
The `Commits:` field is used for reviewer prompt classification, independent of author rewriting. All stages must record their commits.

---

## Verification

1. `cargo build` — verify all call sites for changed function signatures compile. Key: `rewrite_authors_on_worktree` (2 callers), `perform_stash_and_push` (3 call sites in `finalize_stage_session`), `finalize_stage_session` (1 caller in `CliStageRunner::run`).
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Round-trip: `StageContext` with full SHAs → serialized markdown → parsed → equal (full SHAs preserved).
   - Backward compat: no `Commits:` line parses to empty `commits`.
   - Prompt rendering: abbreviated SHAs shown; stage with commits but no records is NOT skipped.
3. Unit test for `rewrite_authors_on_worktree`: empty `commits` slice → returns `Ok(())` without running any git command.
4. Build verification: all `StageContext { ... }` construction sites include `commits: Vec::new()`.

# Plan v19: Show Commits in Context (Issue #314)

## Context and Prior Work

Plans v11–v18 established the core architecture:
- `StageContext.commits: Vec<String>` to record per-attempt agent commits
- `git log --first-parent <baseline>..HEAD` as the detection mechanism
- Conditional env-filter in `rewrite_authors_on_worktree` (rewrites only the detected set)
- Per-attempt `attempt_baseline` captured before each provider loop iteration
- All fatal git operations inside confirmed-repo guards; non-fatal metadata storage for commit records
- Both dispatcher and CLI `overwrite-author` command use shared detection utilities in `zbobr-utility`
- Full SHAs in persisted markdown; abbreviated in prompt-only rendering
- Post-rewrite re-collection for accurate stored SHAs
- `perform_stash_and_push` returns `Vec<String>` of post-rewrite commits; `finalize_stage_session` stores them on all three paths

**Plan v18 had two blocking issues (ctx_rec_35):**

1. **Success-path contradiction**: Plan v18 described the same "warn-and-continue" pattern for all three finalization paths, but also said the success path's existing fatal behavior is preserved. Those two instructions are incompatible. A worker following the shared-pattern description would regress the success path; a worker following the "preserved fatal" note would leave the plan underspecified.

2. **`is_git_repo -> bool` still best-effort**: Plan v18 added `is_git_repo(dir) -> bool` (false on any error) as the gate for baseline capture. This conflates two distinct states — "expected no-repo yet on first run" and "unexpected git failure on a real worktree" — causing both to silently yield an empty baseline. The reviewer required the gate to distinguish those cases, so that unexpected git failures propagate rather than degrade.

---

## Plan v19: Resolving Both Blocking Issues

### Fix 1: Per-Path Finalization Control Flow (No Shared Pattern)

The three paths in `finalize_stage_session` have fundamentally different failure semantics for `perform_stash_and_push`. Describe each path separately.

**Interrupted path** (lines 2006–2016 in cli.rs):
- Call `perform_stash_and_push(..., &commit_baseline)`.
- On success: store returned commits using `store_commits_to_task` (non-fatal helper, see below).
- On failure: log `warn`, store no commits (existing behavior — proceed with `set_state(pending)`).

```
let commits = match self.perform_stash_and_push(..., &commit_baseline).await {
    Ok(c) => c,
    Err(e) => { tracing::warn!("...{e}"); Vec::new() }
};
store_commits_to_task(self, task_id, commits).await; // non-fatal
task_session.set_state(pending_state.clone()).await?;
return Ok(None);
```

**Error path** (lines 2018–2039):
- Call `perform_stash_and_push(..., &commit_baseline)`.
- On success: store returned commits using `store_commits_to_task` (non-fatal).
- On failure: log `warn`, store no commits (existing behavior — proceed with pause/status/signal and `set_state(pending)`).

```
let commits = match self.perform_stash_and_push(..., &commit_baseline).await {
    Ok(c) => c,
    Err(e) => { tracing::warn!("...{e}"); Vec::new() }
};
store_commits_to_task(self, task_id, commits).await; // non-fatal
// ... existing error/pause/status/signal/set_state code unchanged ...
return Ok(outcome.execution_error);
```

**Success path** (lines 2043–2061):
- Call `perform_stash_and_push(..., &commit_baseline)`.
- On **success**: store returned commits using `store_commits_to_task` (non-fatal), then fall through to the rest of the success logic (existing pipeline advance/pause logic).
- On **failure**: execute the **existing fatal behavior exactly** — `tracing::error!(...)`, format error status, `set_pause_with_status_and_signal(...)`, `set_state(pending_state)`, `return Ok(None)`. No commits stored on failure. Do NOT downgrade this to a warning or fall through.

```
let commits = match self.perform_stash_and_push(..., &commit_baseline).await {
    Ok(c) => c,
    Err(e) => {
        // PRESERVED FATAL BEHAVIOR — must not be changed to warn-and-continue
        tracing::error!("Stash/push failed for task #{task_id}: {e}");
        let msg = format!("Stash/push failed: {e}");
        let status = format_error_status(self.config().fixed_offset(), &msg);
        let stage = stage.to_string();
        if let Err(pause_err) = task_session
            .set_pause_with_status_and_signal(status, Signal::go(stage.as_str()))
            .await
        {
            tracing::error!("Failed to pause task #{task_id} after stash/push failure: {pause_err}");
        }
        task_session.set_state(pending_state.clone()).await?;
        return Ok(None);
    }
};
store_commits_to_task(self, task_id, commits).await; // non-fatal
// ... fall through to existing pipeline advance / pause logic unchanged ...
```

`store_commits_to_task` is a small non-fatal helper:
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
Commit storage is non-fatal because the stage has already finished; this is metadata.

---

### Fix 2: `check_is_git_repo` Returns `Result<bool>`

Replace the proposed `is_git_repo(dir) -> bool` with `check_is_git_repo(dir) -> Result<bool>`, using the already-existing `git_check` helper:

```rust
/// Returns Ok(true) if dir is inside a git work tree, Ok(false) if git ran but
/// confirmed it is not a git repository (expected on first run), or Err if git
/// itself failed to run (unexpected — caller should propagate).
pub async fn check_is_git_repo(dir: &Path) -> Result<bool> {
    git_check(dir, &["rev-parse", "--is-inside-work-tree"]).await
}
```

`git_check` already exists in `zbobr-utility/src/lib.rs:218`. It returns:
- `Ok(true)` — exit code 0, confirmed git repo
- `Ok(false)` — exit code non-zero (git ran, but not a git repo)
- `Err(...)` — could not spawn git (unexpected failure)

This distinguishes "expected no-repo on first run" (Ok(false)) from "unexpected git operational failure" (Err).

**At the baseline-capture site** (new code in the provider retry loop, before pushing new `StageContext`):

```rust
let attempt_baseline = match zbobr_utility::check_is_git_repo(&work_dir).await? {
    true  => zbobr_utility::capture_git_head(&work_dir).await?, // fatal: real git repo
    false => String::new(),                                       // graceful: not yet a repo
};
```

The `?` on `check_is_git_repo` means unexpected git failures propagate. `Ok(false)` means gracefully empty. `Ok(true)` means `capture_git_head` is called and is fatal.

**Inside `perform_stash_and_push`** — the existing line 2127:
```rust
let is_git_repo = git_output(work_dir, &["rev-parse", "--is-inside-work-tree"]).await.is_ok();
```
Replace with:
```rust
let is_git_repo = zbobr_utility::check_is_git_repo(work_dir).await?;
```
This ensures unexpected git failures on a real established worktree propagate as errors from `perform_stash_and_push`, rather than silently skipping stash, rewrite, and commit collection. The `Ok(false)` case (gracefully not a repo) is preserved for first-run scenarios.

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

**Add `check_is_git_repo`** (returns `Result<bool>`, wraps `git_check`):
```rust
pub async fn check_is_git_repo(dir: &Path) -> Result<bool> {
    git_check(dir, &["rev-parse", "--is-inside-work-tree"]).await
}
```
- `Ok(true)` = confirmed git repo
- `Ok(false)` = confirmed not a git repo (expected no-repo case)
- `Err(...)` = unexpected git failure

**Add `capture_git_head`** (returns `Result<String>`):
```rust
pub async fn capture_git_head(dir: &Path) -> Result<String> {
    git_output(dir, &["rev-parse", "HEAD"]).await
}
```

**Add `collect_agent_commits`** (returns `Result<Vec<String>>`):
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

**Update `rewrite_authors_on_worktree` signature** to accept explicit commit set:
```rust
pub async fn rewrite_authors_on_worktree(
    work_dir: &Path,
    lower_bound: &str,      // range lower bound for filter-branch traversal scope
    commits: &[String],     // exact full SHAs to rewrite (from first-parent detection)
    git_user_name: &str,
    git_user_email: &str,
) -> Result<()>
```
- If `commits.is_empty()` → return `Ok(())` immediately.
- Build the range `<lower_bound>..HEAD` for `filter-branch` traversal.
- The `--env-filter` shell script checks `$GIT_COMMIT` against a space-separated list of full SHAs embedded in the script. Author/committer env vars are set only when the commit hash matches, leaving second-parent user commits untouched.
- Example env-filter logic:
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
- **Persist path** (`Display` / `serialize_context` / GitHub backend round-trips): emit **full SHAs** to preserve identity through re-parse, e.g. `` Commits: `<sha1>` `<sha2>` `` when non-empty.
- **Prompt-mode rendering**: emit **shortened SHAs** (first 12 chars) for readability. Prompt-mode is never reparsed.
- `from_str` / parsing: detect `COMMITS_LABEL` lines, parse backtick-wrapped tokens as commits.
- Prompt-mode skip fix: change the stage-skip condition to `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }` so stages with commits but no records are included in prompt rendering.

### 4. Commit capture and wiring — `zbobr-dispatcher/src/cli.rs`

**`perform_stash_and_push`** signature change:
```rust
async fn perform_stash_and_push(
    self: &Arc<Self>,
    task_id: u64,
    work_dir: &Path,
    role: &str,
    pipeline_name: &Pipeline,
    commit_baseline: &str,         // new parameter
) -> anyhow::Result<Vec<String>>   // changed return type
```

- Replace line 2127 (`let is_git_repo = git_output(...).is_ok()`) with:
  `let is_git_repo = zbobr_utility::check_is_git_repo(work_dir).await?;`
- Inside the `if is_git_repo` block, after all existing stash/update/rewrite/push logic:
  ```rust
  let commits = if !commit_baseline.is_empty() {
      zbobr_utility::collect_agent_commits(work_dir, commit_baseline).await? // fatal
  } else {
      Vec::new()
  };
  return Ok(commits);
  ```
- Outside `if is_git_repo` (non-repo case): `return Ok(Vec::new())`.

**`finalize_stage_session`** signature change (add `commit_baseline: &str`):
- Implement the **three separate per-path control flows** described in Fix 1 above. Do not use a shared pattern; describe each path individually.
- Specifically:
  - Interrupted path: warn-and-continue on failure; non-fatal commit storage on success.
  - Error path: warn-and-continue on failure; non-fatal commit storage on success.
  - **Success path**: existing fatal behavior exactly preserved on failure (error log, pause with status and signal, set_state(pending), return Ok(None)); non-fatal commit storage on success, then fall through to existing pipeline advance logic.

**`CliStageRunner::run`** — per-attempt baseline capture (inside provider retry loop, before pushing new `StageContext`):
```rust
let attempt_baseline = match zbobr_utility::check_is_git_repo(&work_dir).await? {
    true  => zbobr_utility::capture_git_head(&work_dir).await?,
    false => String::new(),
};
```

**Retry path** (before `continue`):
```rust
if !attempt_baseline.is_empty() {
    let pre_commits = zbobr_utility::collect_agent_commits(&work_dir, &attempt_baseline).await?;
    if config.overwrite_author && !pre_commits.is_empty() {
        zbobr_utility::rewrite_authors_on_worktree(
            &work_dir, &attempt_baseline, &pre_commits,
            &config.git_user_name, &config.git_user_email,
        ).await?;
        let post_commits = zbobr_utility::collect_agent_commits(&work_dir, &attempt_baseline).await?;
        store_retry_commits(&role_session, post_commits).await;
    } else {
        store_retry_commits(&role_session, pre_commits).await;
    }
}
continue;
```

All git operations on the retry path are fatal (`?`).

`store_retry_commits` is a non-fatal helper using `role_session.modify_task`:
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

**Thread `attempt_baseline` to `finalize_stage_session`**: pass `&attempt_baseline` from its computation site through the caller at lines 681–691.

**Update all three `perform_stash_and_push` call sites** in `finalize_stage_session` to pass `commit_baseline`.

### 5. CLI command — `zbobr/src/commands.rs`

Update `overwrite_author`:
1. After `fetch_refs`, call `zbobr_utility::collect_agent_commits(&repo_dir, dest_branch).await?` to get the first-parent agent commit set.
2. If empty: print "No agent commits detected; nothing to rewrite." and return.
3. In `!dry_run` path: call `rewrite_authors_on_worktree(&repo_dir, dest_branch, &agent_commits, ...)`.
4. In dry-run path: show only commits in `agent_commits` (use `--first-parent` in the `git log` invocation for the dry-run output, or just print the pre-collected set).

### 6. Reviewer prompt — `zbobr/src/init.rs`

Add guidance to `REVIEWER_PROMPT`:

> When classifying commits as agent vs user: commits whose full hashes appear in ANY `Commits:` field anywhere in the task context (across all stages and all retry attempts) are known agent and system commits. Commits absent from ALL such lists are likely user-introduced and should be accepted as-is without questioning them.

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext`; update construction sites |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL`; `commits` in `MdStage`; Display: full SHAs in persist path, abbreviated in prompt-only; from_str; from/into_stage_context; prompt-mode skip fix |
| `zbobr-utility/src/lib.rs` | Add `check_is_git_repo` (wraps `git_check`, returns `Result<bool>`); add `capture_git_head`; add `collect_agent_commits`; update `rewrite_authors_on_worktree` signature with `commits: &[String]` and conditional env-filter |
| `zbobr-dispatcher/src/cli.rs` | `perform_stash_and_push`: add `commit_baseline` param, change return to `Vec<String>`, use `check_is_git_repo` (replaces `.is_ok()` at line 2127), collect commits inside; `finalize_stage_session`: add `commit_baseline` param, per-path control flow (interrupted/error: warn-and-continue, success: fatal-on-failure preserved exactly); provider retry loop: baseline capture with `check_is_git_repo`; retry path: fatal collection, optional rewrite, post-rewrite re-collection |
| `zbobr/src/commands.rs` | `overwrite_author`: `collect_agent_commits` before rewrite; pass set to `rewrite_authors_on_worktree` |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` |

---

## Key Design Decisions

**Why `check_is_git_repo` returns `Result<bool>` instead of `bool`?**
The previous `bool` approach (`.is_ok()`) conflates "not a git repo yet" (`Ok(false)`) with "git failed unexpectedly" (`Err`). Both returned `false`, so unexpected git failures silently produced empty baselines. `Result<bool>` preserves the three-way distinction: real repo, expected non-repo, unexpected failure. The existing `git_check` function already implements this pattern.

**Why replace the existing `is_git_repo` line in `perform_stash_and_push` too?**
Consistency: once `check_is_git_repo` exists, the existing `.is_ok()` pattern at line 2127 is a latent bug — unexpected git failures would silently skip stash, rewrite, and commit collection on a real established worktree. Replacing it ensures unexpected failures propagate from `perform_stash_and_push` rather than silently degrade.

**Why describe finalization paths separately rather than using a shared template?**
The three paths have fundamentally different failure semantics for `perform_stash_and_push`. Using a shared template for all three was the source of the v18 contradiction. The success path must retain its existing fatal behavior (pause + signal + return) because a stash/push failure on a completed stage is a significant problem requiring manual intervention. The interrupted/error paths are already in a degraded state where warn-and-continue is appropriate.

**Why `perform_stash_and_push` returns `Vec<String>`?**
It is the function that already knows both the `is_git_repo` state (now via `check_is_git_repo`) and has access to `commit_baseline`. Having it collect and return post-rewrite commits avoids duplicating the collection logic across three callers in `finalize_stage_session`.

**Why post-rewrite re-collection?**
`git filter-branch` rewrites commit objects; their SHAs change. Storing pre-rewrite SHAs would make the stage record invalid. Re-collecting from the same `attempt_baseline` with `--first-parent` after rewrite returns the actual live SHAs.

**Why full SHAs in persisted markdown?**
The GitHub backend persists context as markdown and re-parses it. Abbreviated hashes would permanently lose SHA identity on the first round-trip, breaking the `$GIT_COMMIT` comparison in the env-filter. Full SHAs in normal serialization; abbreviation only in prompt-mode rendering (never reparsed).

**Why store commits even when `overwrite_author` is false?**
The `Commits:` field is for reviewer prompt classification, independent of author rewriting. All stages must record their agent commits.

---

## Verification

1. `cargo build` — verify all changed function signatures compile. Key callers: `rewrite_authors_on_worktree` (2 callers), `perform_stash_and_push` (3 call sites in `finalize_stage_session`), `finalize_stage_session` (1 caller in `CliStageRunner::run`).
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Round-trip: `StageContext` with full SHAs → serialized markdown → parsed → equal.
   - Backward compat: no `Commits:` line parses to empty `commits`.
   - Prompt rendering: abbreviated SHAs shown; stage with commits but no records is NOT skipped.
3. Unit test for `rewrite_authors_on_worktree`: empty `commits` slice → returns `Ok(())` without running any git command.
4. Build verification: all `StageContext { ... }` construction sites include `commits: Vec::new()`.
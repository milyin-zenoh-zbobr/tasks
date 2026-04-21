# Implementation Plan: Show Commits Belonging to Stage

## Objective

Track which Git commits belong to each pipeline stage, display them in the user-facing view, and fix `rewrite_authors_on_worktree` to scope its rewrite only to the current stage's commits (preventing SHA corruption of previous stages' commit lists).

---

## Rationale and Key Design Decisions

- **Closest analogue**: `output_link` and `prompt_link` on `StageInfo` — both are optional fields set at different lifecycle points (start and end) and surfaced in the markdown view via `MdStage`. The new `from_sha`/`commits` follow the same pattern but live on `StageContext` (not `StageInfo`) since they are operational, not executor metadata.
- **`from_sha` scoped rewrite vs full-range rewrite**: The core bug is that `rewrite_authors_on_worktree` uses `dest_branch..HEAD` which rewrites ALL commits above the base. After stage 2 rewrites, stage 1's stored commit SHAs become invalid. Fix: pass `from_sha` (the HEAD before stage started) as the range start so only the current stage's commits are rewritten.
- **Collect commits before `update_worktree`** (first push): Worktree sync may add a merge commit. We want only the agent's commits, so we snapshot `from_sha..HEAD` before any push operation modifies HEAD.
- **Collect rewritten SHAs after `rewrite_authors_on_worktree` but before second `update_worktree`**: At that moment HEAD is the rewritten tip, and `from_sha..HEAD` yields the new SHAs accurately.
- **Backward compat for missing `from_sha`**: Old stages with no `from_sha` fall back to the original `base_branch..HEAD` rewrite behavior. No corruption risk since those stages have no stored SHA lists.

---

## Files to Modify

### 1. `zbobr-api/src/task.rs` — Extend `StageContext`

Add two fields to `StageContext`:

```rust
#[serde(default, skip_serializing_if = "Option::is_none")]
pub from_sha: Option<String>,   // HEAD SHA captured before stage started

#[serde(default, skip_serializing_if = "Vec::is_empty")]
pub commits: Vec<String>,        // full commit SHAs introduced during this stage
```

`from_sha` is set once at stage start (same value for each retry attempt in the provider loop). `commits` is set at stage end after all git operations. Both are optional so existing serialized data deserializes without error (unknown-fields-ignored policy already in place).

**Update all struct-literal constructions of `StageContext`** throughout the codebase to add `from_sha: None, commits: vec![]`. Affected sites (from grep): `zbobr-api/src/task.rs`, `zbobr-api/src/context/json.rs`, `zbobr-task-backend-github/src/separator.rs`, `zbobr-dispatcher/src/cli.rs`.

---

### 2. `zbobr-task-backend-github/src/separator.rs` — Preserve new fields in `merge_stage`

`merge_stage` currently constructs `StageContext { info, records }`, dropping any other fields. After this change it must also merge `from_sha` and `commits`:

- **`from_sha`**: use same priority as `info` — take from `new`, then `curr`, then `orig`. It is set once and never changes.
- **`commits`**: use same priority — take from `new` if non-empty, else `curr`, else `orig`. It is set once (at stage end) and then only updated during the same stage run via the rewrite path.

Also update the test helper `fn stage(...)` and any other `StageContext` literals in separator tests.

---

### 3. `zbobr-utility/src/lib.rs` — Narrow `rewrite_authors_on_worktree` range

Rename parameter `dest_branch` → `range_start` to make it clear the argument can be either a branch name or a commit SHA. No other signature change (return type stays `Result<()>`). The git filter-branch command uses `{range_start}..HEAD` — same substitution as before.

The caller in the dispatcher will pass `from_sha` (scoped to the current stage). The caller in `zbobr/src/commands.rs` continues to pass `dest_branch` (intentional full-branch rewrite, unchanged behavior).

---

### 4. `zbobr-dispatcher/src/cli.rs` — Two-phase change

#### Phase A: Capture `from_sha` at stage start

In `StageSession::run()`, between the work-dir setup and the provider retry loop, capture the current HEAD:

```rust
let from_sha: Option<String> = git_output(&work_dir, &["rev-parse", "HEAD"]).await.ok();
```

Pass this into each `StageContext` pushed inside the retry loop:

```rust
task.context.stages.push(StageContext {
    info: StageInfo { ... },
    records: Vec::new(),
    from_sha: from_sha.clone(),
    commits: vec![],
});
```

This means all retry attempts for the same logical stage share the same baseline SHA.

#### Phase B: Collect commits and update stage context at stage end

In `perform_stash_and_push`:

1. After the `is_git_repo` check, read the task snapshot to retrieve `from_sha = task.context.stages.last()?.from_sha`.
2. **Before the first `update_worktree` call**, collect agent commits if `is_git_repo` and `from_sha` is `Some`:
   ```
   pre_commits = git rev-list --reverse {from_sha}..HEAD
   ```
   Store `pre_commits` into `task.context.stages.last_mut().commits` via `modify_task`. This persists the agent's original SHAs immediately, so they are visible even if a later step fails.
3. Proceed with first `update_worktree` (merge + push).
4. If `config.overwrite_author && is_uptodate && is_git_repo`:
   - If `from_sha` is `Some` AND `pre_commits` is non-empty:
     - Call `zbobr_utility::rewrite_authors_on_worktree(work_dir, from_sha, name, email)` — rewrites only `from_sha..HEAD`.
     - Collect new SHAs: `git rev-list --reverse {from_sha}..HEAD`.
     - Overwrite `task.context.stages.last_mut().commits` with the rewritten SHAs.
     - Proceed with second `update_worktree` (push rewritten commits).
   - Else (no `from_sha`, old-style fallback): call `rewrite_authors_on_worktree(work_dir, base_branch, ...)` — original broad range, no SHA list stored. This preserves backward compat for stages started before this change.

A helper `collect_commits(work_dir: &Path, from_sha: &str) -> Result<Vec<String>>` should be extracted (using `git rev-list --reverse {from_sha}..HEAD`) to avoid duplication.

---

### 5. `zbobr-api/src/context/mod.rs` — Render commits in user-facing view

Add a `commits: Vec<String>` field to `MdStage`. In `MdStage::from_stage_context`, copy `stage.commits.clone()`.

In `MdStage::fmt`, **non-prompt mode only** (`!self.for_prompt`), if `self.commits` is non-empty, emit an indented line after the title:

```
  Commits: `abc1234` `def5678` `0a1b2c3` ...
```

Display the first 7 characters of each SHA (standard Git short SHA). This line appears between the title line and the first record (or at the end if no records).

Prompt mode (`for_prompt = true`) must NOT include the commits line — agents don't need this metadata.

---

### 6. `zbobr/src/commands.rs` — No functional change needed

The existing call passes a branch name as `dest_branch` (renamed to `range_start`). The semantics are unchanged: manual full-branch author rewrite. The return type of `rewrite_authors_on_worktree` stays `Result<()>` so no call-site change is needed. Just rename the parameter at the call site to match.

---

## Impacted Test Fixtures

Anywhere `StageContext { info: ..., records: ... }` appears as a struct literal needs `from_sha: None, commits: vec![]` added:
- `zbobr-api/src/context/json.rs` — `sample_stage()`
- `zbobr-api/src/task.rs` — test helpers
- `zbobr-task-backend-github/src/separator.rs` — `fn stage(...)` and multiple inline literals

---

## Constraints and Edge Cases

- **Empty commit range**: If `pre_commits` is empty (agent made no commits), skip the filter-branch call entirely. Storing `commits: []` is correct.
- **Non-git work dir**: `from_sha` is `None`, `pre_commits` is empty — skip all commit tracking. The `is_git_repo` guard already handles this.
- **No `from_sha` (old-style stages)**: Fall back to original `base_branch` rewrite, no commit list stored. Safe because there are no stored SHAs to corrupt.
- **Serialization backward compat**: `skip_serializing_if` on both new fields means old readers see no change. New readers treat absent fields as `None`/`[]`.
- **`merge_stage` in separator**: Must be updated or `from_sha`/`commits` are dropped on the next concurrent description merge. This is a blocking correctness issue.

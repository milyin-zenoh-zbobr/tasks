# Plan: Show Commits in Context (Issue #314) — Final Revision

## Goal
When a stage finishes (in any outcome that successfully pushes), record the short git commit hashes made during that stage in the stage's context entry. These should be visible in both user and prompt views. Update the reviewer prompt to define "user commits" as commits not listed in any stage record.

---

## Closest Analogs

- **`MdStageTitle` in `zbobr-api/src/context/stage_title.rs`**: uses `try_parse_next_backtick` for backtick-wrapped tokens; the commits line format follows the same backtick pattern. `PROMPT_LABEL` / `OUTPUT_LABEL` constants there are the pattern for `const &str` labels.
- **`output_link` recording (lines 614–643, `cli.rs`)**: the `modify_task` closure pattern for updating the last `StageContext` after an operation.
- **`is_git_repo` check in `perform_stash_and_push`**: the pattern for graceful git failure handling with `.is_ok()` / `.ok()`.
- **`MdContext::from_str` (lines 547–622, `context/mod.rs`)**: the authoritative context parse path — this is where new line-type detection must be added.

---

## Architecture

### 1. Domain model — `zbobr-api/src/task.rs`

Add a `commits` field to `StageContext`:

```rust
pub struct StageContext {
    pub info: StageInfo,
    pub records: Vec<ContextRecord>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub commits: Vec<String>,
}
```

`Vec<String>` of short (7-char abbreviated) SHA hashes. `serde(default)` keeps existing data round-trip unchanged. `skip_serializing_if = "Vec::is_empty"` keeps JSON compact.

Also add `commits: Vec::new()` to every `StageContext { ... }` construction site (the constructor in `run_session` at line ~545, plus any test `StageContext` literals).

---

### 2. Markdown serialization — `zbobr-api/src/context/mod.rs`

#### 2a. `MdStage` struct

Add `commits: Vec<String>` field.

#### 2b. `MdStage::Display`

After writing all records (end of `fmt`), if `commits` is non-empty, write a line:
```
  Commits: `abc1234` `def5678`
```
Two-space indent (matching non-checkbox records). Use a module-level `const COMMITS_LABEL: &str = "Commits"` to prevent string divergence between serializer and parser. Write in both prompt and non-prompt mode.

#### 2c. `MdContext::from_str` — the authoritative parse path

**Key architectural fact**: `MdStage::from_str` is NOT on the actual context deserialization path. The public `parse_context()` function calls `MdContext::from_str`, which processes lines directly. Adding detection only to `MdStage::from_str` would have no effect. The change must go into `MdContext::from_str`.

In the line-by-line loop of `MdContext::from_str`, after the `MdRecord::try_parse` check and before the `"- "` stage-title check, add a branch to detect and parse commit lines:

```
if trimmed.starts_with("Commits: ") || trimmed == "Commits:" {
    // extract backtick-wrapped tokens and push to current_stage.commits
}
```

Extract backtick tokens by finding paired backtick characters. Inline this simple two-pointer extraction (find `\`` open, find `\`` close, extract inner text) rather than importing the `try_parse_next_backtick` helper from `stage_title.rs`, to keep the dependency simple.

This branch must error if `current_stage` is `None` (same as the existing records error).

#### 2d. `MdStage::from_stage_context`

Add: copy `stage.commits.clone()` → `MdStage.commits`.

#### 2e. `MdStage::into_stage_context`

Add: copy `md.commits` → `StageContext.commits`.

#### 2f. Prompt-mode inclusion fix — `MdContext::from_task_context`

Current (line 651):
```rust
if for_prompt && md_stage.records.is_empty() { continue; }
```
Change to:
```rust
if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }
```
This ensures stages with commits but no records appear in agent prompts.

---

### 3. Baseline capture and commit recording — `zbobr-dispatcher/src/cli.rs`

#### 3a. Capture baseline before execution (in `run_session` retry loop)

After the new `StageContext` is pushed (line ~561) and before `execute_tool` is called, capture the commit count baseline as `Option<usize>`:

```rust
let start_commit_count: Option<usize> = {
    let base_branch = self.zbobr.repo_backend().branch().to_string();
    git_output(&work_dir, &["rev-list", "--count", &format!("origin/{base_branch}..HEAD")])
        .await
        .ok()
        .and_then(|s| s.trim().parse::<usize>().ok())
    // None = git not available yet or parse failed — skip recording for this stage
};
```

The critical change from previous plans: **if baseline capture fails for any reason, the value is `None` (not `0`).** A `None` baseline means we skip commit recording for that stage entirely (not silently misattribute all existing commits). This is the correct behavior for "not a git repo yet" (first stage) and also for any transient git failure.

#### 3b. Pass `start_commit_count: Option<usize>` to `finalize_stage_session`

Add parameter to the function signature. Update the single call site (line ~682).

#### 3c. Extract helper: `collect_stage_commits`

Add a small private async helper:

```rust
async fn collect_stage_commits(
    work_dir: &Path,
    base_branch: &str,
    start_count: Option<usize>,
) -> Vec<String>
```

Implementation:
1. If `start_count` is `None`, return empty vec (can't compute delta reliably).
2. Run `git log --format=%h origin/<base_branch>..HEAD` to get all short hashes (newest-first).
3. If that fails or returns empty, return empty vec.
4. `new_count = all_hashes.len() - start_count`. If `new_count <= 0`, return empty vec.
5. Return `all_hashes[..new_count]` (the newest `new_count` commits are the ones added this stage).

**Why count-based delta works through author rewrite**: `rewrite_authors_on_worktree` rewrites ALL commits ahead of base (changes SHAs) but does NOT add or remove commits. So commit count is preserved through rewrite. The new SHAs captured after push are the canonical final hashes (correct).

**Why `Option<usize>` is safe**: if baseline was captured as `None`, we return empty vec. No commits are attributed. The reviewer prompt will treat these as user commits, which is the safe fallback — better than wrongly attributing old commits to the current agent stage.

#### 3d. Call commit recording in ALL outcome paths that call `perform_stash_and_push`

The adversarial review (ctx_rec_4) correctly identifies that `perform_stash_and_push` can succeed in all three outcome paths (interrupted, error, success). An agent stage can make commits even if it ends in interruption or error. Those commits must be recorded so they are not misidentified as "user commits" by the reviewer.

Refactor the three paths as follows:

**Interrupted path** (currently lines 2006-2016):
```rust
if outcome.execution_interrupted {
    let push_ok = self
        .perform_stash_and_push(task_id, work_dir, stage.as_str(), pipeline)
        .await
        .is_ok();
    if push_ok {
        self.record_stage_commits(&task_session, work_dir, base_branch, start_commit_count).await;
    }
    task_session.set_state(pending_state.clone()).await?;
    ...
    return Ok(None);
}
```

**Error path** (currently lines 2018-2038):
```rust
if let Some(e) = outcome.execution_error.as_ref() {
    let push_ok = self
        .perform_stash_and_push(task_id, work_dir, stage.as_str(), pipeline)
        .await
        .is_ok();
    if push_ok {
        self.record_stage_commits(&task_session, work_dir, base_branch, start_commit_count).await;
    }
    ...
    return Ok(outcome.execution_error);
}
```

**Success path** (currently lines 2043-2061):
```rust
if let Err(e) = self
    .perform_stash_and_push(task_id, work_dir, stage.as_str(), pipeline)
    .await
{
    // handle failure: warn, set pause, return
    ...
    return Ok(None);
}
// push succeeded
self.record_stage_commits(&task_session, work_dir, base_branch, start_commit_count).await;
// ... continue to compute post-stage signal
```

Where `record_stage_commits` is a small async helper that calls `collect_stage_commits` and, if non-empty, calls `task_session.modify_task` to set `stage.commits` on the last stage (logging a warning if modify_task fails, same as existing output_link pattern).

The `base_branch` string needed for `git log` is obtainable from `self.repo_backend().branch()` — same pattern already used in `perform_stash_and_push` at line 2174.

---

### 4. Reviewer prompt update — `zbobr/src/init.rs`

In `REVIEWER_PROMPT`, update step 5 (line 921):

Old:
> "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user according to the git history."

New:
> "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user. User commits are commits whose short hashes do **not** appear in any stage's `Commits:` line in the task context; agent commits are explicitly listed there under each stage."

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext`; update all construction sites |
| `zbobr-api/src/context/mod.rs` | Add `commits` to `MdStage`; serialize in `Display`; parse in `MdContext::from_str`; map through `from_stage_context`/`into_stage_context`; fix prompt-mode inclusion check |
| `zbobr-dispatcher/src/cli.rs` | Capture `start_commit_count: Option<usize>` before execution; add parameter to `finalize_stage_session`; add `collect_stage_commits` and `record_stage_commits` helpers; call commit recording after successful stash+push in ALL three outcome paths |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` step 5 |

---

## Key Design Decisions

1. **Parse in `MdContext::from_str`, not `MdStage::from_str`**: The actual context parsing path goes through `MdContext::from_str` line by line. `MdStage::from_str` is not called during `parse_context()`.

2. **`Option<usize>` baseline, no `0` fallback**: If baseline capture fails for any reason, we skip commit recording for that stage. This is the safe fallback — better than misattributing all existing commits to the current stage. First-stage "not yet a git repo" case naturally produces `None` and no commits are recorded (which is correct: no commits yet).

3. **ALL three outcome paths**: Commit recording runs after any successful `perform_stash_and_push`, regardless of whether the stage ended in interruption, error, or success. An agent that errors or gets interrupted can still have made commits; these must be labeled as agent commits.

4. **Count-based delta, not hash subtraction**: `start_commit_count` is captured before execution. After stash/push/rewrite, `all_hashes.len() - start_count` gives exactly the new commits. Works correctly through author rewrite (which changes SHAs but not commit count).

5. **`COMMITS_LABEL` constant**: Prevents `"Commits"` from diverging between serializer and parser.

6. **Prompt-mode inclusion**: Update the empty-records skip check to also check `md_stage.commits.is_empty()`.

7. **Warning on failure, never fail the stage**: All new git operations use `.ok()` / `.is_ok()` and emit `tracing::warn!` on failure, matching existing patterns in `perform_stash_and_push`.

---

## Tests

Unit tests in `zbobr-api/src/context/mod.rs`:
- Roundtrip: serialize a `StageContext` with `commits = vec!["abc1234", "def5678"]`, verify markdown contains `  Commits: \`abc1234\` \`def5678\`` and parse back gives equal commits.
- Backward compat: `StageContext` with empty `commits` produces no `Commits:` line; existing markdown without a `Commits:` line parses with empty `commits`.
- Prompt inclusion: a stage with commits and no records is NOT skipped in prompt mode (i.e., `from_task_context` with `for_prompt=true` includes it).

The commit delta logic in `cli.rs` requires a live git repo; no new unit tests needed — existing integration tests cover the stage execution path.

# Plan: Show Commits in Context (Issue #314) — Final Revision (v4)

## Goal
When a stage finishes (in any outcome that successfully pushes), record the short git commit hashes made during that stage in the last stage's context entry. These should be visible in both user and prompt views. Update the reviewer prompt to identify agent commits from the `Commits:` field.

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

Also add `commits: Vec::new()` to every `StageContext { ... }` construction site (around lines 545–556 in the retry loop, plus any test `StageContext` literals).

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

Extract backtick tokens by finding paired backtick characters (two-pointer scan: find open backtick, find close backtick, extract inner text). This can be implemented inline or via the `try_parse_next_backtick` helper from `stage_title.rs`.

This branch must error if `current_stage` is `None` (same as the existing records error).

#### 2d. `MdStage::from_stage_context`

Add: copy `stage.commits.clone()` → `MdStage.commits`.

#### 2e. `MdStage::into_stage_context`

Add: copy `md.commits` → `StageContext.commits`.

#### 2f. Prompt-mode inclusion fix — `MdContext::from_task_context`

Current:
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

#### 3a. Capture baseline ONCE before the retry loop (critical fix for issue #1)

**Blocking issue from ctx_rec_6**: The previous plan captured the baseline *inside* the retry loop (once per provider attempt). If provider A fails and makes commits (count goes from 5 to 7), then provider B's baseline would be 7. Provider B's 1 commit would be recorded, but provider A's 2 commits would never appear in any stage record. The reviewer prompt would then treat those 2 commits as "user commits" — wrong.

**Fix**: Capture baseline ONCE at around line 522–525, before `loop {`:

```rust
let base_branch = self.zbobr.repo_backend().branch().to_string();
let start_commit_count: Option<usize> =
    git_output(&work_dir, &["rev-list", "--count", &format!("origin/{base_branch}..HEAD")])
        .await
        .ok()
        .and_then(|s| s.trim().parse::<usize>().ok());
// None = git not available or parse failed — see finalize_stage_session for handling
```

Pass `start_commit_count` to `finalize_stage_session` as a new parameter.

#### 3b. `collect_stage_commits` helper (private async fn)

```rust
async fn collect_stage_commits(
    work_dir: &Path,
    base_branch: &str,
    start_count: Option<usize>,
) -> Vec<String>
```

Implementation:
1. Run `git log --format=%h origin/<base_branch>..HEAD` to get all short hashes (newest-first). If this fails or returns empty, return `vec![]`.
2. `total = all_hashes.len()`.
3. `n_new = total - start_count.unwrap_or(0)`. If `n_new <= 0`, return `vec![]`.
4. Return `all_hashes[..n_new]` (the newest `n_new` commits are the ones added this stage/cycle).

**`Option<usize>` semantics**:
- `Some(n)`: there were `n` known commits before this stage cycle started. New commits = total - n.
- `None`: git was unavailable or count failed before execution. Use `unwrap_or(0)` — this is safe: if the git repo didn't exist before (and `perform_stash_and_push` still succeeded), then all current commits are agent-made. If baseline failed due to a transient git error, treating `start_count` as 0 is over-inclusive (attributes existing commits too), but this is a rare/degenerate case. The reviewer prompt (see §4) uses language that tolerates this ambiguity without being incorrect.

**Why count-based delta works through author rewrite**: `rewrite_authors_on_worktree` rewrites all commits ahead of base (changes SHAs) but does NOT add or remove commits. The count delta is preserved. The final hashes after push/rewrite are the canonical correct hashes to record.

#### 3c. `record_stage_commits` helper

A small async helper that:
1. Calls `collect_stage_commits(work_dir, base_branch, start_commit_count)`.
2. If non-empty, calls `task_session.modify_task` to set `stage.commits` on the LAST stage entry in `task.context.stages`.
3. Logs a `tracing::warn!` on `modify_task` failure (same pattern as `output_link`), never propagates the error.

By recording in the **last** `StageContext` entry, all commits from the entire retry cycle (provider A failed + provider B succeeded) are attributed to provider B's entry. Provider A's entry has no `Commits:` line. This is correct: all commits that made it into the pushed worktree are labeled as agent commits somewhere in the context.

#### 3d. Call commit recording in ALL three outcome paths that call `perform_stash_and_push`

**Interrupted path** (lines 2006-2016):
```rust
let push_ok = self
    .perform_stash_and_push(task_id, work_dir, stage.as_str(), pipeline)
    .await
    .is_ok();
if push_ok {
    self.record_stage_commits(&task_session, &work_dir, &base_branch, start_commit_count).await;
}
```

**Error path** (lines 2018-2038):
Same pattern: record if push succeeded.

**Success path** (lines 2043-2061):
```rust
if let Err(e) = self
    .perform_stash_and_push(task_id, work_dir, stage.as_str(), pipeline)
    .await
{ /* handle failure */ return Ok(None); }
// push succeeded
self.record_stage_commits(&task_session, &work_dir, &base_branch, start_commit_count).await;
```

The `base_branch` needed for `git log` is available via `self.repo_backend().branch()` — same pattern already used in `perform_stash_and_push` at line 2174.

---

### 4. Reviewer prompt update — `zbobr/src/init.rs`

In `REVIEWER_PROMPT` (line 921):

Old:
> "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user according to the git history."

New:
> "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user. Commits listed under a stage's `Commits:` field in the task context are known agent commits; commits not listed there are likely user commits (though attribution may be incomplete for stages where commit tracking was unavailable)."

**Why this wording resolves ctx_rec_6 issue #2**: The previous prompt said "unlisted = user commit" absolutely, which conflicted with the dispatcher's `None`-baseline silent-skip behavior. The new wording says "listed = known agent" (positive claim) and "unlisted = **likely** user" (probabilistic, acknowledging incomplete attribution). This is internally consistent: the dispatcher can silently skip recording when baseline capture fails, and the reviewer uses the word "likely" rather than a hard rule. The feature still achieves its goal — the reviewer can reliably identify agent commits from the `Commits:` field when it is present.

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext`; update all construction sites |
| `zbobr-api/src/context/mod.rs` | Add `commits` to `MdStage`; serialize in `Display`; parse in `MdContext::from_str`; map through `from_stage_context`/`into_stage_context`; fix prompt-mode inclusion check |
| `zbobr-dispatcher/src/cli.rs` | Capture `start_commit_count: Option<usize>` ONCE before retry loop; add parameter to `finalize_stage_session`; add `collect_stage_commits` and `record_stage_commits` helpers; call commit recording after successful stash+push in ALL three outcome paths |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` step 5 |

---

## Key Design Decisions

1. **Parse in `MdContext::from_str`, not `MdStage::from_str`**: The actual context parsing path goes through `MdContext::from_str` line by line. `MdStage::from_str` is not called during `parse_context()`.

2. **Baseline captured ONCE before the retry loop**: This is the critical fix for the provider-retry attribution bug. All commits from the entire retry cycle (across all provider attempts) are attributable. They are recorded in the LAST `StageContext` entry after the final push.

3. **`Option<usize>` with `unwrap_or(0)` in delta computation**: If baseline capture fails (None), we treat it as 0 — record all commits ahead of origin/base as agent commits. This is safe for the "not a git repo yet" case (all commits are agent-made) and over-inclusive in the degenerate transient-failure case (a rare non-issue). We do NOT silently skip attribution for `None` — we attempt to record.

4. **ALL three outcome paths**: Commit recording runs after any successful `perform_stash_and_push`, regardless of interruption/error/success.

5. **Count-based delta, not hash subtraction**: Works correctly through author rewrite (changes SHAs, not counts).

6. **`COMMITS_LABEL` constant**: Prevents `"Commits"` from diverging between serializer and parser.

7. **Softer reviewer prompt language**: "likely user commits" with explicit "attribution may be incomplete" disclaimer resolves the dispatcher/prompt semantic inconsistency identified in ctx_rec_6.

---

## Tests

Unit tests in `zbobr-api/src/context/mod.rs`:
- Roundtrip: serialize a `StageContext` with `commits = vec!["abc1234", "def5678"]`, verify markdown contains `  Commits: \`abc1234\` \`def5678\`` and parse back gives equal commits.
- Backward compat: `StageContext` with empty `commits` produces no `Commits:` line; existing markdown without a `Commits:` line parses with empty `commits`.
- Prompt inclusion: a stage with commits and no records is NOT skipped in prompt mode.

The commit delta logic in `cli.rs` requires a live git repo; no new unit tests needed.
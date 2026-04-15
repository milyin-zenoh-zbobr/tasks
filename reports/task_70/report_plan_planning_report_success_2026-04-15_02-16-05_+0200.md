# Plan: Show Commits in Context (Issue #314) — Revised

## Goal
When a stage finishes successfully, record the short git commit hashes made during that stage in the stage's context entry. These should be visible in both user and prompt views. Update the reviewer prompt to define "user commits" as commits not listed in any stage record.

---

## Closest Analogs

- **`MdStageTitle` in `zbobr-api/src/context/stage_title.rs`**: uses `try_parse_next_backtick` helper for backtick-wrapped tokens in serialization/deserialization. The commits line format follows this same backtick pattern.
- **`output_link` recording in `run_session` (`zbobr-dispatcher/src/cli.rs` line ~614–643)**: the pattern for updating the last `StageContext` via `modify_task` after an operation succeeds.
- **`is_git_repo` check in `perform_stash_and_push`**: the pattern for gracefully skipping git operations when the work directory is not a git repo.
- **`PROMPT_LABEL` / `OUTPUT_LABEL` constants in `stage_title.rs`**: the pattern for `const &str` labels used in both serialization and parsing to prevent divergence.

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

`Vec<String>` of short (7-char abbreviated) SHA hashes. Default empty so existing data round-trips unchanged. `skip_serializing_if = "Vec::is_empty"` keeps the JSON compact.

Also add `commits: Vec::new()` to the existing `StageContext { ... }` construction in `run_session`.

---

### 2. Markdown serialization — `zbobr-api/src/context/mod.rs`

#### 2a. `MdStage` struct

Add `commits: Vec<String>` field.

#### 2b. `MdStage::Display`

After writing all records (end of `fmt`), if `commits` is non-empty, write a line:
```
  Commits: `abc1234` `def5678`
```
Two-space indent (matching non-checkbox records). Use a `const COMMITS_LABEL: &str = "Commits"` constant in the module. This line is written in both prompt and non-prompt mode so agents can see commit hashes.

Example:
```rust
const COMMITS_LABEL: &str = "Commits";
// in fmt():
if !self.commits.is_empty() {
    write!(f, "  {COMMITS_LABEL}:")?;
    for h in &self.commits {
        write!(f, " `{h}`")?;
    }
    writeln!(f)?;
}
```

#### 2c. `MdContext::from_str` — the authoritative parse path

**Key finding**: `MdStage::from_str` is NOT the actual parsing path for context documents. The `parse_context()` public function calls `MdContext::from_str`, which parses the document line-by-line. `MdStage::from_str` is a separate, unused-in-this-path implementation that won't affect normal parsing.

The `MdContext::from_str` loop currently handles:
1. Empty lines → skip
2. `<!-- stage -->` markers → set `after_stage_marker`
3. Lines passing `MdRecord::try_parse()` → append to current stage's records
4. Lines starting with `"- "` → try to parse as stage title
5. Anything else → `bail!("Unrecognized line in context: ...")`

**Change**: Before step 4 (the `"- "` check), add detection of `Commits:` lines. A line whose trimmed form starts with `"Commits: "` should be parsed as a commits line by extracting backtick-wrapped tokens (reuse `try_parse_next_backtick` from `stage_title.rs`, or inline equivalent logic since it's in a private module). Store in `current_stage.commits`.

To use `try_parse_next_backtick`, either:
- Make it `pub(super)` in `stage_title.rs` and import it, OR
- Inline the same two-line backtick extraction logic in `mod.rs`

The simpler approach is to inline the extraction since it's trivial (find opening backtick, find closing backtick, extract inner text), keeping dependencies minimal.

#### 2d. `MdStage::from_stage_context`

Add: copy `stage.commits.clone()` → `MdStage.commits`.

#### 2e. `MdStage::into_stage_context`

Add: copy `md.commits` → `StageContext.commits`.

#### 2f. Prompt-mode inclusion fix — `MdContext::from_task_context`

Current: `if for_prompt && md_stage.records.is_empty() { continue; }`

Change to: `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }`

This ensures stages with commits but no records are still included in agent prompts.

---

### 3. Baseline capture and commit collection — `zbobr-dispatcher/src/cli.rs`

**Problem with "subtract previously-recorded" approach**: if the user makes a commit on the work branch between two agent stages, that commit is not in any previous stage, so the subtraction would wrongly attribute it to the next agent stage.

**Correct approach**: capture a commit count baseline BEFORE the agent runs, then compute the delta AFTER stash/push/rewrite.

#### 3a. Capture baseline before execution (in `run_session` loop)

After pushing the new `StageContext` and before calling `execute_tool`, capture `start_commit_count: usize`:

```rust
let start_commit_count = if is_git_repo {
    let base_branch = self.zbobr.repo_backend().branch();
    git_output(&work_dir, &["rev-list", "--count", &format!("origin/{base_branch}..HEAD")])
        .await
        .ok()
        .and_then(|s| s.trim().parse::<usize>().ok())
        .unwrap_or(0)
} else {
    0
};
```

Wait — `is_git_repo` is not available in `run_session` at this point (it's only checked inside `perform_stash_and_push`). Instead, use `.ok()` / `.unwrap_or(0)` to handle the "not a git repo" case gracefully:

```rust
let base_branch = self.zbobr.repo_backend().branch().to_string();
let start_commit_count: usize = git_output(
    &work_dir,
    &["rev-list", "--count", &format!("origin/{base_branch}..HEAD")]
)
.await
.ok()
.and_then(|s| s.trim().parse().ok())
.unwrap_or(0);
```

This uses `git rev-list --count` which returns a number, making it trivial to parse, and silently returns 0 if the work_dir isn't a git repo yet.

#### 3b. Pass `start_commit_count` to `finalize_stage_session`

Add parameter `start_commit_count: usize` to `finalize_stage_session`. Update the single call site (line ~683).

#### 3c. Collect new commits in `finalize_stage_session` success path

In the success path, after `perform_stash_and_push` succeeds (after line 2061, before computing the post-stage signal):

```rust
let base_branch = self.repo_backend().branch().to_string();
let all_hashes: Vec<String> =
    git_output(work_dir, &["log", "--format=%h", &format!("origin/{base_branch}..HEAD")])
        .await
        .unwrap_or_default()
        .lines()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();

let new_commits: Vec<String> = if all_hashes.len() > start_commit_count {
    all_hashes[..all_hashes.len() - start_commit_count].to_vec()
} else {
    Vec::new()
};
```

`git log` outputs newest-first, so the `all_hashes.len() - start_commit_count` newest commits are the ones added during this stage.

If `all_hashes` is empty (git error or not a repo), `new_commits` is empty and nothing is stored.

If `new_commits` is non-empty, update the last stage:

```rust
if !new_commits.is_empty() {
    task_session.modify_task(move |mut task| {
        if let Some(stage) = task.context.stages.last_mut() {
            stage.commits = new_commits;
        }
        task
    }).await?;
}
```

Extract this into a small private async helper `collect_and_record_stage_commits` to keep `finalize_stage_session` readable.

**Why count-based works through author rewrite**: `rewrite_authors_on_worktree` rewrites ALL commits ahead of base (changing SHAs), but does NOT add or remove commits. So the COUNT of commits ahead of base remains the same after rewriting. The new SHAs after rewrite are the ones stored (correct, canonical pushed SHAs). If `start_commit_count` was N and `all_hashes.len()` after rewrite is N+3, those 3 newest-first commits are correctly the new agent commits.

---

### 4. Reviewer prompt update — `zbobr/src/init.rs`

In `REVIEWER_PROMPT`, update step 5:

Old:
> "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user according to the git history."

New:
> "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user. User commits are commits whose short hashes do **not** appear in any stage record in the task context under a `Commits:` line; agent commits are listed there explicitly under their stage."

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext` |
| `zbobr-api/src/context/mod.rs` | Add `commits` to `MdStage`; serialize in `Display`; parse in `MdContext::from_str`; map through `from_stage_context`/`into_stage_context`; fix prompt-mode inclusion check |
| `zbobr-dispatcher/src/cli.rs` | Capture `start_commit_count` before execution; add parameter to `finalize_stage_session`; collect and record new commits in success path |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` step 5 |

---

## Key Design Decisions

1. **Parse in `MdContext::from_str`, not `MdStage::from_str`**: The actual context parsing path goes through `MdContext::from_str` line by line. `MdStage::from_str` is not called during `parse_context()`. Adding detection only to `MdStage::from_str` would have no effect.

2. **Count-based baseline instead of hash subtraction**: Captures `start_commit_count` before execution, computes delta after push. Correctly handles inter-stage user commits (they're counted in the baseline and not attributed to the agent's stage). Works correctly through author-rewrite since rewriting preserves commit count.

3. **`COMMITS_LABEL` constant**: Prevents `"Commits"` string from diverging between serializer and parser.

4. **Prompt-mode inclusion**: Update `if for_prompt && md_stage.records.is_empty()` to also check `md_stage.commits.is_empty()`, so stages with commits-only appear in prompts.

5. **Graceful git failure handling**: All git operations in the new commit collection code use `.ok()` / `.unwrap_or_default()` and never fail the stage on git errors (consistent with existing `tracing::warn` pattern for git failures).

---

## Tests

- Unit test in `zbobr-api/src/context/mod.rs`:
  - Roundtrip: serialize a `StageContext` with `commits = vec!["abc1234", "def5678"]`, verify the markdown contains `  Commits: \`abc1234\` \`def5678\`` and parse it back to get equal commits.
  - Backward compat: a `StageContext` with empty `commits` produces no `Commits:` line; existing markdown without a `Commits:` line parses with empty `commits`.
  - Prompt inclusion: a stage with commits and no records is NOT skipped in prompt mode.

- The commit collection logic in `cli.rs` requires a live git repo; no new unit tests needed there — the existing integration path covers it.

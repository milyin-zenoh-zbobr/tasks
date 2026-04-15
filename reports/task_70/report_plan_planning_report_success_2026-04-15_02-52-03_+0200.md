# Plan: Show Commits in Context (Issue #314) — Final Revision (v5)

## Core Insight (User's Comment)

All previous plans used a count-delta against `origin/<base>..HEAD` *after* `perform_stash_and_push()`. This was fragile because `update_worktree()` (called inside `perform_stash_and_push`) merges user commits from `origin/<work_branch>` and may create merge commits, polluting the count.

The user's insight resolves this cleanly: **all stage commits are always local before the push, and user commits can only arrive during the merge step inside `perform_stash_and_push()`.**

Therefore, capture `origin/<work_branch>..HEAD` *before* calling `perform_stash_and_push()`. This gives the exact set of agent-made commits:
- At stage start, `update_worktree()` syncs local to `origin/<work_branch>`, so `origin/<work_branch>..HEAD = 0`
- During the stage, only the agent makes local commits — the range grows
- User commits only arrive via Phase 8 of `update_worktree()` inside `perform_stash_and_push()` — after capture

This eliminates: baseline counting, count arithmetic, retry-loop parameter threading, and the entire attribution-after-merge bug.

---

## Closest Analog

- **`output_link` recording** (`cli.rs` around line 614–643): the `modify_task` closure pattern for updating the last `StageContext` after a successful operation.
- **`MdStageTitle`** (`zbobr-api/src/context/stage_title.rs`): `PROMPT_LABEL` / `OUTPUT_LABEL` `const &str` pattern for label constants; backtick token format.
- **`MdContext::from_str`** (`zbobr-api/src/context/mod.rs` lines 547–622): the authoritative context parse path where new line-type detection must be added.

---

## Architecture

### 1. Domain model — `zbobr-api/src/task.rs`

Add `commits: Vec<String>` to `StageContext`:

```rust
pub struct StageContext {
    pub info: StageInfo,
    pub records: Vec<ContextRecord>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub commits: Vec<String>,
}
```

Short (7-char abbreviated) SHA hashes. `serde(default)` keeps existing data round-trip unchanged. Update every `StageContext { ... }` construction site (including `cli.rs` line ~545–557 and any test literals) to add `commits: Vec::new()`.

---

### 2. Markdown serialization/parsing — `zbobr-api/src/context/mod.rs`

#### 2a. `MdStage` struct
Add `commits: Vec<String>` field.

#### 2b. `MdStage::Display`
After writing all records, if `commits` is non-empty, emit:
```
  Commits: `abc1234` `def5678`
```
Two-space indent, matching existing non-checkbox record style. Add `const COMMITS_LABEL: &str = "Commits"` at module level — prevents label string from diverging between serializer and parser. Write in both prompt and non-prompt mode (commits are useful in agent prompts too).

#### 2c. `MdContext::from_str` — the authoritative parse path
**Critical**: `MdStage::from_str` is not called during `parse_context()`. The only real parse path is the line-by-line loop in `MdContext::from_str`. Adding detection elsewhere would have no effect.

In the line-by-line loop, between the `MdRecord::try_parse` check and the `"- "` stage-title check, add a branch for commit lines:

```
if trimmed.starts_with(COMMITS_LABEL) {
    // extract backtick-wrapped tokens, push to current_stage.commits
}
```

Extract backtick tokens with a two-pointer scan (open backtick → close backtick → extract inner text). Error if `current_stage` is `None` (same pattern as the record error above).

#### 2d/2e. `MdStage::from_stage_context` / `into_stage_context`
Copy `stage.commits.clone()` ↔ `md.commits`.

#### 2f. Prompt-mode inclusion fix — `MdContext::from_task_context`
Change:
```rust
if for_prompt && md_stage.records.is_empty() { continue; }
```
to:
```rust
if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }
```
Ensures stages with commits but no records appear in agent prompts.

---

### 3. Commit capture and recording — `zbobr-dispatcher/src/cli.rs`

#### 3a. `collect_agent_commits` helper (private async fn)

```rust
async fn collect_agent_commits(work_dir: &Path, work_branch: &str, base_branch: &str) -> Vec<String>
```

1. Try `git log --format=%h origin/<work_branch>..HEAD`. If this succeeds and is non-empty, return those hashes.
2. If that fails (remote work branch doesn't exist yet, e.g., first stage on a new branch), fall back to `git log --format=%h origin/<base_branch>..HEAD`.
3. If git is unavailable or both fail, return `vec![]`.

`work_branch` comes from the task identity (`task.identity().work_branch`), fetched via `self.task_backend().get_task(task_id)` — the same pattern used in `perform_stash_and_push`.

#### 3b. `record_stage_commits` helper (private async fn)

```rust
async fn record_stage_commits(task_session: &TaskSession, commits: Vec<String>)
```

If `commits` is non-empty, calls `task_session.modify_task` to set `commits` on the **last** `StageContext` entry. Logs `tracing::warn!` on `modify_task` failure (same pattern as `output_link`), never propagates.

#### 3c. Capture once, record in all three outcome paths

In `finalize_stage_session`, before the three `perform_stash_and_push` call sites:
1. Fetch the task to get `identity.work_branch` (or empty if identity missing)
2. Call `collect_agent_commits(work_dir, work_branch, base_branch)` once

Then in each of the three outcome paths (interrupted, error, success):
- Interrupted (line ~2006): capture the `perform_stash_and_push` result; if `Ok(())`, call `record_stage_commits`
- Error (line ~2018): same
- Success (line ~2043): call after `perform_stash_and_push` returns `Ok`

Capturing once and reusing the `Vec<String>` across all three mutually exclusive paths is safe because only one path executes.

#### 3d. SHA accuracy note

When `overwrite_author = true`, `rewrite_authors_on_worktree` changes SHAs before the final push. The captured SHAs (from before `perform_stash_and_push`) may differ from the final SHAs on GitHub. This is a known limitation: commit messages still identify the work correctly, and in the common case (`overwrite_author = false`) the SHAs are accurate.

---

### 4. Reviewer prompt update — `zbobr/src/init.rs`

Update step 5 in `REVIEWER_PROMPT` (line ~921):

Old:
> "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user according to the git history."

New:
> "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user. Commits listed under a stage's `Commits:` field in the task context are known agent commits; commits not listed there are likely user commits (attribution may be incomplete for stages where commit tracking was unavailable)."

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext`; update all construction sites |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL` const; `commits` in `MdStage`; serialize in `Display`; parse in `MdContext::from_str`; `from_stage_context`/`into_stage_context` mapping; fix prompt-mode inclusion check |
| `zbobr-dispatcher/src/cli.rs` | `collect_agent_commits` helper; `record_stage_commits` helper; capture + record in `finalize_stage_session` for all three outcome paths |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` step 5 |

---

## Key Design Decisions

1. **`origin/<work_branch>..HEAD` before push**: Directly implements the user's insight. Captures exactly this stage's agent commits with no counting, no baseline, no drift from retries.

2. **Fallback to `origin/<base>..HEAD`**: Handles first-run on a new branch where remote work branch doesn't exist yet.

3. **Capture once before all three paths**: The three outcome paths in `finalize_stage_session` are mutually exclusive — one `Vec<String>` capture is reused.

4. **Parse in `MdContext::from_str` not `MdStage::from_str`**: The real parse path; `MdStage::from_str` is not on the context deserialization path.

5. **`COMMITS_LABEL` const**: Prevents label string divergence between serializer and parser.

6. **Soft reviewer prompt language**: "likely user commits" / "may be incomplete" — honest about the `overwrite_author` edge case.

---

## Tests

Unit tests in `zbobr-api/src/context/mod.rs`:
- **Roundtrip**: `StageContext` with `commits = ["abc1234", "def5678"]` → serialize → markdown contains `  Commits: \`abc1234\` \`def5678\`` → parse back → equal commits.
- **Backward compat**: empty `commits` produces no `Commits:` line; markdown without `Commits:` line parses with empty `commits`.
- **Prompt inclusion**: stage with commits and no records is NOT skipped in prompt mode.

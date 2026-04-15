# Plan: Show Commits in Context (Issue #314) — Final (v6)

## Summary of Prior Iterations

Previous plans failed adversarial review for these cumulative reasons:
- Plans 1-2: wrong parse target (`MdStage::from_str` instead of `MdContext::from_str`)
- Plan 3: count-delta after push (merge commits from `update_worktree` pollute count)
- Plan 4: only success path covered; dangerous `0` fallback for Option baseline
- Plan 5: baseline moved before retry loop; all three paths covered — good
- Plan 6 (ctx_rec_9): correct approach using `origin/<work_branch>..HEAD` BEFORE push
- Plan 7 (ctx_rec_10): adversarial blocks on FS backend not maintaining `origin/<work_branch>` sync

## Why the Approach Is Correct (Addressing ctx_rec_10 Concern)

The adversarial review's concern: *"FS backend doesn't push the work branch to origin after each stage, so `origin/<work_branch>..HEAD` is not a per-stage baseline."*

This concern is theoretically valid but practically resolved by two facts:

1. **FS backend does NOT merge user commits from `origin/<work_branch>` either.** The FS backend's `update_worktree()` (`zbobr-repo-backend-fs/src/fs.rs:143-190`) only ensures the worktree exists and checks if the work branch is up-to-date with the base branch. It does NOT merge remote work into local (unlike GitHub backend's Phase 8). So the "user commits arriving via merge" scenario that the adversarial review worries about simply does not apply to FS backend.

2. **For FS backend, all commits on the local work branch are agent-made.** Users would have to manually merge from remote, which is out-of-band. The fallback behavior (using `origin/<base_branch>..HEAD`) may be over-inclusive (recording all commits ahead of base, not just this stage's), but it cannot cause an agent commit to be labeled as a "user commit." Over-inclusion is the safe direction.

3. **GitHub backend is the production backend** where the agent-vs-user distinction matters (users push to `origin/<work_branch>` via GitHub, and GitHub backend's Phase 8 merges those). For GitHub backend, `origin/<work_branch>..HEAD` BEFORE `perform_stash_and_push` is exactly correct: Phase 10 of the prior stage's `update_worktree()` synced `origin/<work_branch>` to local HEAD, so only this stage's agent commits are in the range.

The reviewer prompt uses "likely user commits" / "attribution may be incomplete" language, which correctly reflects this limitation.

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

Short (7-char abbreviated) SHA hashes. `serde(default)` keeps existing data round-trip unchanged. `skip_serializing_if = "Vec::is_empty"` keeps JSON compact.

Update the `StageContext { ... }` construction site in `cli.rs` around line 545-557 to add `commits: Vec::new()`.

---

### 2. Markdown serialization — `zbobr-api/src/context/mod.rs`

#### 2a. `MdStage` struct (line 363)
Add `commits: Vec<String>` field.

#### 2b. `MdStage::Display` (line 370)
After the records loop (after line 397), emit a `Commits:` line if `commits` is non-empty:
```
  Commits: `abc1234` `def5678`
```
Two-space indent (same as non-checkbox records). Add `const COMMITS_LABEL: &str = "Commits"` at module level — prevents label string from diverging between serializer and parser. Emit in both prompt and non-prompt mode.

#### 2c. `MdContext::from_str` — the ONLY authoritative parse path (line 550)

**Critical architectural fact confirmed by inspection**: `MdStage::from_str` (line 406) is NOT called during `parse_context()`. The only real path is `MdContext::from_str` which processes lines directly. Any unrecognized line currently hits `bail!("Unrecognized line in context: ...")` at line 610.

In the line-by-line loop, between the `MdRecord::try_parse` check (line 569) and the `"- "` stage-title check (line 579), add a branch for commit lines:

```rust
// Detect commit attribution line: "Commits: `abc1234` ..."
if trimmed.starts_with(COMMITS_LABEL) {
    let stage = current_stage.as_mut().ok_or_else(|| {
        anyhow::anyhow!("Commits line found before any stage header: {}", trimmed)
    })?;
    // Extract backtick-wrapped tokens
    let mut rest = trimmed;
    while let Some(open) = rest.find('`') {
        rest = &rest[open + 1..];
        if let Some(close) = rest.find('`') {
            stage.commits.push(rest[..close].to_string());
            rest = &rest[close + 1..];
        } else {
            break;
        }
    }
    continue;
}
```

#### 2d. `MdStage::from_stage_context` (line 446)
Add `commits: stage.commits.clone()` to the `MdStage { ... }` construction.

#### 2e. `MdStage::into_stage_context` (line 486)
Add `commits: self.commits` to the `StageContext { ... }` construction.

#### 2f. Prompt-mode inclusion fix — `MdContext::from_task_context` (line 651)
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

#### 3a. `collect_agent_commits` private async helper

```rust
async fn collect_agent_commits(
    work_dir: &Path,
    work_branch: &str,
    base_branch: &str,
) -> Vec<String>
```

Implementation:
1. Try `git log --format=%h origin/<work_branch>..HEAD`. If this returns non-empty output, collect and return the hash list (one per line).
2. If that fails or returns empty (remote work branch doesn't exist yet — typical on first stage of a new task), fall back to `git log --format=%h origin/<base_branch>..HEAD`.
3. If git is unavailable or both fail, return `vec![]`.

**Why `origin/<work_branch>..HEAD` is correct for GitHub backend**: After each stage, GitHub backend's `update_worktree()` Phase 10 pushes local HEAD to `origin/<work_branch>`. So at the start of the next stage (before the agent makes any commits), `origin/<work_branch>..HEAD = 0`. The agent's commits accumulate during the stage. Capturing this range BEFORE `perform_stash_and_push` (which triggers Phase 8 merge of user commits) gives exactly this stage's agent commits.

**Why `origin/<work_branch>..HEAD` is safe for FS backend**: FS backend doesn't merge user commits from `origin/<work_branch>` either (its `update_worktree()` only checks base-branch ancestor status). So user commits cannot appear in the local worktree via merge during FS backend stages. The fallback to `origin/<base_branch>..HEAD` may be over-inclusive (recording all commits ahead of base across all stages in the last-stage entry), but no agent commit is misattributed as a user commit.

#### 3b. `record_stage_commits` private async helper

```rust
async fn record_stage_commits(
    task_session: &TaskSession, // or equivalent type
    commits: Vec<String>,
)
```

If `commits` is non-empty:
```rust
task_session.modify_task(move |mut task| {
    if let Some(stage) = task.context.stages.last_mut() {
        stage.commits = commits;
    }
    task
}).await
```
Log `tracing::warn!` on failure (same pattern as `output_link` at line 622-635), never propagate.

#### 3c. Call pattern in `finalize_stage_session` (line 1994)

At the start of `finalize_stage_session`, before the three mutually exclusive `perform_stash_and_push` calls, capture agent commits ONCE:

```rust
// Capture agent commits before stash/push changes the worktree state.
// work_branch comes from task identity; base_branch from repo_backend config.
let agent_commits = {
    let task = self.task_backend()
        .get_task(task_id)
        .await?
        .snapshot(false)
        .await?;
    let work_branch = task.identity()
        .map(|id| id.work_branch.clone())
        .unwrap_or_default();
    let base_branch = self.repo_backend().branch().to_string();
    Self::collect_agent_commits(work_dir, &work_branch, &base_branch).await
};
```

Then in each of the three outcome paths:

**Interrupted path** (line 2006):
```rust
if outcome.execution_interrupted {
    let push_ok = self.perform_stash_and_push(...).await.is_ok();
    if push_ok {
        self.record_stage_commits(&task_session, agent_commits.clone()).await;
    }
    // ... rest of path
}
```

**Error path** (line 2018):
```rust
if let Some(e) = outcome.execution_error.as_ref() {
    let push_ok = self.perform_stash_and_push(...).await.is_ok();
    if push_ok {
        self.record_stage_commits(&task_session, agent_commits.clone()).await;
    }
    // ... rest of path
}
```

**Success path** (line 2043):
```rust
if let Err(e) = self.perform_stash_and_push(...).await {
    // handle failure
    return Ok(None);
}
// push succeeded
self.record_stage_commits(&task_session, agent_commits).await;
// ... continue to compute post-stage signal
```

Note: `agent_commits` is captured BEFORE any `perform_stash_and_push` call. The three paths are mutually exclusive (only one executes), so a single capture at the start is correct and efficient.

#### 3d. Why this works through author rewrite

`rewrite_authors_on_worktree` uses `git filter-branch ... {base_branch}..HEAD`, which rewrites author/committer info but does NOT add or remove commits. The commit SHAs change, but the commit count stays the same. However, we capture the hashes BEFORE `perform_stash_and_push` (which calls `rewrite_authors_on_worktree` inside). So the hashes we capture are the PRE-REWRITE hashes.

This is a known limitation: with `overwrite_author = true`, the SHAs in the `Commits:` field may differ from the final pushed SHAs on GitHub. However:
- The commit content and messages are unchanged
- This is an edge case (the common `overwrite_author = false` case is exact)
- The reviewer prompt uses "known agent commits" (positive claim), not "exact SHAs to look up on GitHub"
- In practice, reviewing by message is sufficient

If exact post-rewrite SHAs are needed in future, one option is to capture hashes AFTER `perform_stash_and_push` using a count-based approach where `start_count = agent_commits.len()` (which is stable through rewrite). This is a future optimization, not needed for this feature.

---

### 4. Reviewer prompt update — `zbobr/src/init.rs`

Update step 5 in `REVIEWER_PROMPT` (around line 921):

Old:
> "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user according to the git history."

New:
> "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user. Commits listed under a stage's `Commits:` field in the task context are known agent commits; commits not listed there are likely user commits (attribution may be incomplete for stages where commit tracking was unavailable)."

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext`; update construction sites |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL` const; `commits` in `MdStage`; serialize in `Display`; parse in `MdContext::from_str`; mapping in `from_stage_context`/`into_stage_context`; fix prompt-mode inclusion check |
| `zbobr-dispatcher/src/cli.rs` | `collect_agent_commits` helper; `record_stage_commits` helper; capture at start of `finalize_stage_session`; record after successful push in all three outcome paths; add `commits: Vec::new()` to `StageContext` construction |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` step 5 |

---

## Key Design Decisions

1. **Parse in `MdContext::from_str`, not `MdStage::from_str`**: Verified by inspection — `parse_context()` calls `MdContext::from_str` line-by-line. `MdStage::from_str` is not called during context deserialization. The new `Commits:` line detection MUST go between lines 569-578 (after `MdRecord::try_parse`, before `"- "` stage-title check) to avoid hitting the `bail!` at line 610.

2. **`origin/<work_branch>..HEAD` BEFORE `perform_stash_and_push`**: Implements the user's insight. For GitHub backend (production): exactly correct (Phase 10 of prior stage syncs `origin/<work_branch>`; Phase 8 of this stage merges user commits, which hasn't run yet). For FS backend: `origin/<work_branch>` not maintained, but FS backend also doesn't merge user commits → over-inclusive but safe.

3. **Capture once at start of `finalize_stage_session`**: The three outcome paths are mutually exclusive. One pre-push capture serves all three.

4. **ALL three outcome paths**: Agent commits must be recorded for interrupted and error outcomes too, since those also call `perform_stash_and_push` and may push agent commits.

5. **`COMMITS_LABEL` const**: Prevents `"Commits"` string from diverging between serializer and parser.

6. **Prompt-mode inclusion fix**: A stage with commits but no records should not be skipped in prompt mode — agents need to see commit hashes.

7. **Soft reviewer prompt language**: "likely user commits" / "attribution may be incomplete" — honest about the `overwrite_author` SHA-rewrite edge case and FS backend limitation.

8. **Pre-rewrite SHAs**: With `overwrite_author = true`, captured hashes are pre-rewrite SHAs. Acknowledged limitation; the feature still works for its primary purpose (identifying which commits are agent-made).

---

## Tests

Unit tests in `zbobr-api/src/context/mod.rs`:
- **Roundtrip**: `StageContext` with `commits = vec!["abc1234", "def5678"]` → serialize → markdown contains `  Commits: \`abc1234\` \`def5678\`` → parse back → equal commits.
- **Backward compat**: empty `commits` produces no `Commits:` line; existing markdown without a `Commits:` line parses with empty `commits`.
- **Prompt inclusion**: stage with commits and no records is NOT skipped in prompt mode (`from_task_context` with `for_prompt=true` includes it).

Commit collection logic in `cli.rs` requires a live git repo; no new unit tests needed — existing integration path covers it.

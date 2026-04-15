# Plan v16: Show Commits in Context (Issue #314)

## Context and Prior Work

Plans v11–v15 established the core architecture:
- `StageContext.commits: Vec<String>` field to record per-attempt agent commits
- `git log --first-parent <baseline>..HEAD` as the detection mechanism (user commits enter only via merges as second parents)
- Per-attempt `attempt_baseline` captured before each provider loop iteration
- Retry-path rewrite is fatal on failure (Plan v15)
- Reviewer prompt references union of all `Commits:` fields across all context stages (Plan v15)

**Plan v15 had two blocking issues (ctx_rec_29):**

**Issue 1:** `rewrite_authors_on_worktree` used `git filter-branch ... '<lower_bound>..HEAD'`, which rewrites ALL commits reachable from HEAD but not from the baseline — including second-parent (user) commits. The first-parent detection mechanism produces a strict subset. The two definitions did not match.

**Issue 2:** The CLI `overwrite-author` command still called `rewrite_authors_on_worktree` with `dest_branch` as a range bound, rewriting every commit in `dest_branch..HEAD` including user commits.

---

## Plan v16 Changes

### Core Fix: Rewrite Operates on the Exact Detected Commit Set

Change `rewrite_authors_on_worktree` in `zbobr-utility/src/lib.rs` to accept an explicit list of full SHA commits to rewrite instead of a range. The git `filter-branch` env-filter becomes **conditional**: it rewrites a commit's author only if `$GIT_COMMIT` appears in the provided set.

**New signature:**
```rust
pub async fn rewrite_authors_on_worktree(
    work_dir: &Path,
    lower_bound: &str,   // range lower bound for filter-branch traversal scope
    commits: &[String],  // full SHAs: the exact set to rewrite (from first-parent detection)
    git_user_name: &str,
    git_user_email: &str,
) -> Result<()>
```

- If `commits` is empty, return `Ok(())` immediately (no-op).
- Build `lower_bound..HEAD` as the traversal range (limits which commits filter-branch visits, preventing modification of ancient history). Second-parent user commits within this range are visited but NOT rewritten because they won't be in the `commits` set.
- The env-filter shell script checks `$GIT_COMMIT` against the space-separated list of full SHAs embedded in the command. Only commits present in the list get their author/committer overwritten.
- Full SHAs are required for `$GIT_COMMIT` comparison (it is always a full 40-char SHA). Short hashes must not be used here.

### New Shared Utility: `collect_agent_commits`

Add `collect_agent_commits` to `zbobr-utility/src/lib.rs` (alongside `rewrite_authors_on_worktree`) so both the dispatcher and the CLI command can use it:

```rust
pub async fn collect_agent_commits(dir: &Path, lower_bound: &str) -> Vec<String>
    // guard: if lower_bound is empty, return Vec::new()
    // git log --first-parent --format=%H <lower_bound>..HEAD
    // on error: tracing::warn!, return Vec::new()
```

Returns full SHAs (format `%H`). The `--first-parent` flag ensures only the local-branch chain is traversed, excluding merged user commits.

Also add `capture_git_head` to `zbobr-utility/src/lib.rs`:
```rust
pub async fn capture_git_head(dir: &Path) -> Result<String>
    // git rev-parse HEAD
```

These two functions replace the dispatcher-local helpers described in Plan v15. They need to be in `zbobr-utility` because the CLI command (in `zbobr` crate) also needs them; `zbobr` already depends on `zbobr-utility`.

### Fix 2: CLI `overwrite-author` Command

In `zbobr/src/commands.rs`, `overwrite_author` function: before calling `rewrite_authors_on_worktree`, call `collect_agent_commits(repo_dir, dest_branch)` to determine the first-parent agent commit set. Pass that set as the `commits` parameter. Update the call site accordingly.

If the detected set is empty, skip rewriting with a user-facing note (e.g., "No agent commits detected between `dest_branch` and HEAD; nothing to rewrite.").

The dry-run `git log` in this function should also use `--first-parent` to show only the commits that would actually be rewritten.

---

## Complete Architecture (all changes)

### 1. Domain model — `zbobr-api/src/task.rs`

Add to `StageContext`:
```rust
#[serde(default, skip_serializing_if = "Vec::is_empty")]
pub commits: Vec<String>,
```
Update `StageContext { ... }` constructor at `zbobr-dispatcher/src/cli.rs:545` to include `commits: Vec::new()`.

Commits are stored as full SHAs (`%H`).

### 2. Utility functions — `zbobr-utility/src/lib.rs`

**Add `capture_git_head`:**
```rust
pub async fn capture_git_head(dir: &Path) -> Result<String>
// git rev-parse HEAD → trimmed stdout
```

**Add `collect_agent_commits`:**
```rust
pub async fn collect_agent_commits(dir: &Path, lower_bound: &str) -> Vec<String>
// guard: if lower_bound is empty → Vec::new()
// git log --first-parent --format=%H <lower_bound>..HEAD
// on error: tracing::warn!, return Vec::new()
```
Returns full SHAs.

**Change `rewrite_authors_on_worktree` signature:**
```rust
pub async fn rewrite_authors_on_worktree(
    work_dir: &Path,
    lower_bound: &str,   // range lower bound for filter-branch traversal
    commits: &[String],  // exact full SHAs to rewrite
    git_user_name: &str,
    git_user_email: &str,
) -> Result<()>
```
- If `commits.is_empty()` → return `Ok(())`.
- Embed the full SHA list in the env-filter shell command as a space-separated string stored in a shell variable. The env-filter tests `$GIT_COMMIT` against that list and only sets the `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env vars when a match is found.
- Use `git filter-branch -f --env-filter '...' '<lower_bound>..HEAD'` as the traversal range.

### 3. Markdown serialization — `zbobr-api/src/context/mod.rs`

- Add `const COMMITS_LABEL: &str = "Commits"`.
- Add `commits: Vec<String>` to `MdStage` struct.
- `MdStage::from_stage_context`: `commits: stage.commits.clone()`.
- `MdStage::into_stage_context`: `commits: self.commits`.
- `MdStage` Display: emit `  Commits: \`abc1234...\` \`def5678...\`` (abbreviated from full SHA for readability, e.g., first 12 chars) when non-empty.
- `MdStage::from_str` / `MdContext::from_str`: detect `COMMITS_LABEL` line, parse backtick-wrapped tokens as commits. Store full SHA if the token looks full-length, otherwise store as-is (round-trip compatibility with abbreviated display).
- Prompt-mode skip fix: `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }`.

### 4. Commit capture and wiring — `zbobr-dispatcher/src/cli.rs`

Remove the dispatcher-local `capture_git_head` and `collect_agent_commits` helpers described in v14/v15; they are now in `zbobr-utility`.

**`perform_stash_and_push`** (line 2115): add `commit_baseline: &str` parameter. Replace `&base_branch` with `commit_baseline` in the `rewrite_authors_on_worktree` call. Change the call to:
```rust
zbobr_utility::rewrite_authors_on_worktree(
    work_dir,
    commit_baseline,
    &agent_commits,         // ← new: pass detected commits
    &config.git_user_name,
    &config.git_user_email,
).await?;
```
Where `agent_commits` is computed just before the call:
```rust
let agent_commits = zbobr_utility::collect_agent_commits(work_dir, commit_baseline).await;
```
(Inside `perform_stash_and_push`, after `update_worktree`.) Keep the guard `config.overwrite_author && is_uptodate && is_git_repo && !commit_baseline.is_empty()`.

Update all three callers in `finalize_stage_session` to thread `commit_baseline`.

**`finalize_stage_session`** (line ~1994): add `commit_baseline: &str` parameter.

**Per-attempt baseline** (inside provider retry loop, before StageContext push at line ~532):
```rust
let attempt_baseline = zbobr_utility::capture_git_head(&work_dir)
    .await
    .unwrap_or_else(|e| { tracing::warn!("Failed to capture git HEAD: {e}"); String::new() });
```

**Retry path** (before `continue` at line ~670):
```rust
if !attempt_baseline.is_empty() && config.overwrite_author {
    let retry_commits = zbobr_utility::collect_agent_commits(&work_dir, &attempt_baseline).await;
    zbobr_utility::rewrite_authors_on_worktree(
        &work_dir,
        &attempt_baseline,
        &retry_commits,
        &config.git_user_name,
        &config.git_user_email,
    ).await?;  // fatal on error
    role_session.modify_task(|mut task| {
        if let Some(stage) = task.context.stages.last_mut() { stage.commits = retry_commits; }
        task
    }).await.unwrap_or_else(|e| tracing::warn!("Failed to store retry commits: {e}"));
} else if !attempt_baseline.is_empty() {
    let retry_commits = zbobr_utility::collect_agent_commits(&work_dir, &attempt_baseline).await;
    role_session.modify_task(|mut task| {
        if let Some(stage) = task.context.stages.last_mut() { stage.commits = retry_commits; }
        task
    }).await.unwrap_or_else(|e| tracing::warn!("Failed to store retry commits: {e}"));
}
continue;
```
(Note: commit capture happens whether or not `overwrite_author` is set; rewriting only happens when it is set.)

**Final path** (after `finalize_stage_session`):
```rust
let finalize_result = self.zbobr.finalize_stage_session(..., &attempt_baseline).await?;
let all_commits = zbobr_utility::collect_agent_commits(&work_dir, &attempt_baseline).await;
role_session.modify_task(|mut task| {
    if let Some(stage) = task.context.stages.last_mut() { stage.commits = all_commits; }
    task
}).await.unwrap_or_else(|e| tracing::warn!("Failed to store final commits: {e}"));
if let Some(e) = finalize_result { server_handle.abort(); return Err(e); }
server_handle.abort();
return Ok(());
```
Commit capture after `finalize_stage_session` ensures finalization merge commits are included.

### 5. CLI command caller — `zbobr/src/commands.rs`

Update `overwrite_author`:
1. After `fetch_refs`, call `zbobr_utility::collect_agent_commits(&repo_dir, dest_branch).await` to get the exact first-parent agent commit set.
2. If the set is empty, print "No agent commits detected; nothing to rewrite." and return.
3. In the `!dry_run` path, pass `&agent_commits` to `rewrite_authors_on_worktree`.
4. In the dry-run `git log` path, use `--first-parent` in the git log invocation to show only what would actually be rewritten.

### 6. Reviewer prompt — `zbobr/src/init.rs`

Add guidance to `REVIEWER_PROMPT`:

> When classifying commits as agent vs user: commits whose full or abbreviated hashes appear in ANY `Commits:` field anywhere in the task context (across all stages and all retry attempts) are known agent and system commits. Commits absent from ALL such lists are likely user-introduced and should be accepted as-is without questioning them.

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext` |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL`; `commits` in `MdStage`; Display (abbreviated); from_str; from/into_stage_context; prompt-mode fix |
| `zbobr-utility/src/lib.rs` | Add `capture_git_head`; add `collect_agent_commits`; add `commits: &[String]` param and conditional env-filter to `rewrite_authors_on_worktree` |
| `zbobr-dispatcher/src/cli.rs` | Remove local helpers; per-attempt baseline capture; retry-path: detect commits then conditionally rewrite (fatal), then store; `commit_baseline` param chain through `finalize_stage_session` → `perform_stash_and_push`; `perform_stash_and_push`: detect commits then rewrite; final-path commit capture after finalization |
| `zbobr/src/commands.rs` | `overwrite_author`: call `collect_agent_commits` first, pass result to `rewrite_authors_on_worktree`; dry-run log uses `--first-parent` |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` |

---

## Key Design Decisions

**Why conditional env-filter (not revised range)?**
Narrowing the range to first-parent commits is not directly expressible as a git revision range. The conditional env-filter is the correct mechanism: `filter-branch` visits the full range (to avoid missing commits needing rewriting), but the shell script inside the env-filter only applies the author override when `$GIT_COMMIT` is in the known-agent set. This precisely matches the detection boundary.

**Why full SHAs in `commits`?**
`$GIT_COMMIT` in git env-filter is always a full 40-char SHA. Matching against short hashes would be unreliable. Full SHAs are stored in `StageContext.commits`; markdown display may abbreviate them (e.g., first 12 chars) for readability, but parsing must round-trip correctly.

**Why `collect_agent_commits` and `capture_git_head` in `zbobr-utility`?**
Both the dispatcher (`zbobr-dispatcher`) and the CLI (`zbobr`) need these functions. `zbobr-utility` is a shared dependency of both. Moving them there avoids duplication and prevents the CLI command from having a divergent implementation.

**Why commit capture even when `overwrite_author` is false?**
The task requirement is: detect → rewrite (if needed) → store. Storing commits in the stage context is independent of whether author rewriting is enabled. The commits field is needed for the reviewer prompt classification regardless.

**Why `--first-parent` in `collect_agent_commits`?**
User insight: "all stage commits are always local and any user commits may only come on merging." `update_worktree` in `zbobr-repo-backend-github` merges user changes as second parents. `--first-parent` follows only the local branch chain, excluding those merged user commits.

**Why capture commits AFTER `finalize_stage_session` for the final path?**
`finalize_stage_session` → `perform_stash_and_push` → `update_worktree` creates finalization merge commits. These system merge commits are agent/system commits and must appear in `Commits:`. Capturing before would miss them. Note: `rewrite_authors_on_worktree` inside `perform_stash_and_push` already detects and rewrites commits at that point; the post-finalization `collect_agent_commits` re-detects to include finalization commits in the stored set.

**Why retry-path rewrite failure is fatal?**
If a retry-path rewrite fails, those commits keep incorrect authors. The final `perform_stash_and_push` rewrite only covers the last attempt's `attempt_baseline..HEAD`, so earlier attempts' commits are never corrected. Making it fatal is the safe choice, consistent with `perform_stash_and_push` behavior.

---

## Verification

1. `cargo build` — no compile errors; verify all call sites for `rewrite_authors_on_worktree` and `collect_agent_commits` compile.
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Roundtrip: `StageContext` with commits (full SHAs) → markdown → parse back → equal.
   - Backward compat: empty commits → no `Commits:` line; parsing without `Commits:` → empty.
   - Prompt inclusion: stage with commits but no records is NOT skipped in prompt mode.
3. Unit test for `rewrite_authors_on_worktree`: empty `commits` slice → returns `Ok(())` without running any git command.
4. Integration: verify retry path stores commits per attempt.
5. Integration: verify final path stores commits including finalization merge commits.
6. Integration: `overwrite_author` dry-run shows only first-parent commits.
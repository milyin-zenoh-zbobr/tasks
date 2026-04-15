# Plan v17: Show Commits in Context (Issue #314)

## Context and Prior Work

Plans v11–v16 established the core architecture:
- `StageContext.commits: Vec<String>` to record per-attempt agent commits
- `git log --first-parent <baseline>..HEAD` as the detection mechanism (user commits enter only via merges as second parents)
- Per-attempt `attempt_baseline` captured before each provider loop iteration
- Conditional env-filter in `rewrite_authors_on_worktree` (rewrites only commits in detected set, not all commits in the range)
- Retry-path rewrite failure is fatal
- Both the dispatcher flow and the CLI `overwrite-author` command use the same shared detection utilities

**Plan v16 had three blocking issues (ctx_rec_31):**

1. **Retry-path stores pre-rewrite SHAs** — after `git filter-branch` rewrites commits, their SHAs change. Storing the pre-rewrite SHA list makes the stored set invalid.
2. **Abbreviated hashes are lossy in the GitHub-backed persistence model** — the task context is persisted as markdown (serialized via `serialize_context`) and re-parsed (via `parse_context`). Abbreviated display in normal serialization permanently corrupts stored SHA identity.
3. **`collect_agent_commits` silently returns empty on error** — this function is now correctness-critical (defines which commits are rewritten and recorded); best-effort degradation is unsafe here.

---

## Plan v17: Resolving All Three Blocking Issues

### Fix 1: Post-Rewrite Re-Collection

Whenever `rewrite_authors_on_worktree` is called, the caller **must re-collect** the first-parent commit set after the rewrite completes, using the same `attempt_baseline` parameter. The re-collected (post-rewrite) hashes are what get stored in `stage.commits`.

**Correct order on both retry-path and finalization-path:**
1. `collect_agent_commits(work_dir, &attempt_baseline)?`  → `pre_commits` (used as input to rewrite)
2. `rewrite_authors_on_worktree(work_dir, &attempt_baseline, &pre_commits, ...)`  → may fail fatally
3. `collect_agent_commits(work_dir, &attempt_baseline)?`  → `post_commits` (stored in stage record)
4. `stage.commits = post_commits`

On the **finalization path** (inside `perform_stash_and_push`), step 3 must happen after `perform_stash_and_push` returns (to capture finalization merge commits), using the same logic as v16 described. Step 3 re-collects from the same `attempt_baseline` passed through.

When **`overwrite_author` is false**, the rewrite steps (1→2→3) are skipped, but commit storage (one call to `collect_agent_commits` → store) still happens for the reviewer prompt.

### Fix 2: Full SHAs in Persisted Markdown; Abbreviation Only in Prompt Rendering

The markdown `Commits:` line in **all serialization paths** must use **full 40-character SHAs**. This ensures round-trip fidelity through the GitHub-backed persistence.

- `MdStage::fmt` (used for task body / context storage): emit full SHAs.
- `MdStage::prompt_text` or equivalent prompt-mode rendering path: may abbreviate to first 12 chars for readability.
- The parser `from_str` always reads tokens as-is (preserving full SHAs when emitted by normal serialization).
- No "store full if full-length, otherwise store as-is" ambiguity: the serializer always emits full SHAs, so the parser always reads full SHAs.

### Fix 3: `collect_agent_commits` Returns `Result<Vec<String>>`

Change the signature to:
```rust
pub async fn collect_agent_commits(dir: &Path, lower_bound: &str) -> Result<Vec<String>>
```

Behavior:
- Guard: if `lower_bound` is empty → return `Ok(Vec::new())`.
- `git log --first-parent --format=%H <lower_bound>..HEAD`
- On error: return `Err(...)`.

**Callers in correctness-critical paths** (retry-path, finalization-path, `overwrite-author` command rewrite path): propagate errors with `?`, making them fatal.

**Callers in optional-display paths** (e.g. dry-run log): use `.unwrap_or_else(|e| { tracing::warn!(...); Vec::new() })`.

---

## Complete Architecture

### 1. Domain model — `zbobr-api/src/task.rs`

Add to `StageContext`:
```rust
#[serde(default, skip_serializing_if = "Vec::is_empty")]
pub commits: Vec<String>,
```
Commits are stored as full 40-char SHAs.

Update all `StageContext { ... }` construction sites to include `commits: Vec::new()`.

### 2. Utility functions — `zbobr-utility/src/lib.rs`

**Add `capture_git_head`:**
```rust
pub async fn capture_git_head(dir: &Path) -> Result<String>
// git rev-parse HEAD → trimmed stdout
```

**Add `collect_agent_commits`:**
```rust
pub async fn collect_agent_commits(dir: &Path, lower_bound: &str) -> Result<Vec<String>>
// guard: lower_bound is empty → Ok(Vec::new())
// git log --first-parent --format=%H <lower_bound>..HEAD
// on error: Err(...)
```

**Change `rewrite_authors_on_worktree` signature** to accept explicit commit set:
```rust
pub async fn rewrite_authors_on_worktree(
    work_dir: &Path,
    lower_bound: &str,   // range lower bound for filter-branch traversal scope
    commits: &[String],  // exact full SHAs to rewrite (from first-parent detection)
    git_user_name: &str,
    git_user_email: &str,
) -> Result<()>
```
- If `commits.is_empty()` → return `Ok(())` immediately (no-op).
- Build `<lower_bound>..HEAD` as the traversal range for `git filter-branch`.
- The `--env-filter` shell script checks `$GIT_COMMIT` against the full SHA list embedded as a space-separated variable. Author/committer env vars are set **only** when `$GIT_COMMIT` is found in that list.
- Full SHAs are used for comparison; `$GIT_COMMIT` in git env-filter is always a full 40-char SHA.

### 3. Markdown serialization — `zbobr-api/src/context/mod.rs`

- Add `const COMMITS_LABEL: &str = "Commits"`.
- Add `commits: Vec<String>` to `MdStage` struct.
- `MdStage::from_stage_context`: `commits: stage.commits.clone()`.
- `MdStage::into_stage_context`: `commits: self.commits`.
- `MdStage` Display (the persisted serialization path): emit full SHAs, e.g. `  Commits: \`<full_sha1>\` \`<full_sha2>\`` when non-empty. No abbreviation.
- Prompt-mode rendering: emit shortened SHAs (first 12 chars) for readability, since prompt rendering is never reparsed.
- `from_str` / parsing: detect `COMMITS_LABEL` lines, parse backtick-wrapped tokens as commits. Tokens are always full SHAs in normal round-trips; stored as-is.
- Prompt-mode skip fix: `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }`.

### 4. Commit capture and wiring — `zbobr-dispatcher/src/cli.rs`

Remove any dispatcher-local `capture_git_head` / `collect_agent_commits` helpers (they now live in `zbobr-utility`).

**Per-attempt baseline capture** (inside provider retry loop, before `StageContext` push):
```rust
let attempt_baseline = zbobr_utility::capture_git_head(&work_dir)
    .await
    .unwrap_or_else(|e| { tracing::warn!("Failed to capture git HEAD: {e}"); String::new() });
```
(Warning-and-empty is acceptable here because baseline capture is best-effort; missing it means commit detection for this attempt degrades gracefully to empty list.)

**Retry path** (before `continue`, when execution failed and more providers remain):
```rust
if !attempt_baseline.is_empty() {
    // always collect; conditionally rewrite
    let pre_commits = zbobr_utility::collect_agent_commits(&work_dir, &attempt_baseline).await?;
    if config.overwrite_author && !pre_commits.is_empty() {
        zbobr_utility::rewrite_authors_on_worktree(
            &work_dir,
            &attempt_baseline,
            &pre_commits,
            &config.git_user_name,
            &config.git_user_email,
        ).await?;  // fatal on error
        // Post-rewrite re-collection
        let post_commits = zbobr_utility::collect_agent_commits(&work_dir, &attempt_baseline).await?;
        store_stage_commits(&role_session, post_commits).await;
    } else {
        store_stage_commits(&role_session, pre_commits).await;
    }
}
continue;
```
Where `store_stage_commits` is a small closure/helper that calls `role_session.modify_task` to set `stage.commits` on the last stage. Non-fatal (`unwrap_or_else(|e| tracing::warn!(...))`).

**`finalize_stage_session`** receives `attempt_baseline: &str` as an additional parameter. It passes `attempt_baseline` through to `perform_stash_and_push`.

**`perform_stash_and_push`** receives `commit_baseline: &str` as an additional parameter.
Inside the `overwrite_author` guard, change the call to:
```rust
if config.overwrite_author && is_uptodate && is_git_repo {
    let pre_commits = zbobr_utility::collect_agent_commits(work_dir, commit_baseline).await?;
    zbobr_utility::rewrite_authors_on_worktree(
        work_dir,
        commit_baseline,
        &pre_commits,
        &config.git_user_name,
        &config.git_user_email,
    ).await?;
    let is_uptodate = self.update_worktree(&identity).await?;
    if !is_uptodate {
        anyhow::bail!("Merge conflict while pushing rewritten commits for task #{task_id}");
    }
}
```
The pre_commits are used only as the rewrite target; the final commit set is captured AFTER `perform_stash_and_push` returns.

**After `finalize_stage_session`** returns `Ok(None)` on the success path:
```rust
let post_commits = zbobr_utility::collect_agent_commits(&work_dir, &attempt_baseline)
    .await
    .unwrap_or_else(|e| { tracing::warn!("Failed to collect final commits: {e}"); Vec::new() });
store_stage_commits(&role_session, post_commits).await;
```
(Warning-and-empty here is acceptable because the stage has completed successfully; failure to record commits is a best-effort record-keeping issue, not a correctness block.)

**Update all callers** of `finalize_stage_session` and `perform_stash_and_push` to thread `attempt_baseline` / `commit_baseline`.

### 5. CLI command — `zbobr/src/commands.rs`

Update `overwrite_author` function:
1. After `fetch_refs`, call `zbobr_utility::collect_agent_commits(&repo_dir, dest_branch).await?` to get the exact first-parent agent commit set.
2. If the set is empty, print "No agent commits detected; nothing to rewrite." and return.
3. In the `!dry_run` path:
   - Call `rewrite_authors_on_worktree(&repo_dir, dest_branch, &agent_commits, ...)`.
   - (No post-rewrite re-collection needed here since the CLI path does not store commits to any stage record; the user is doing a manual one-time fix.)
4. In the dry-run `git log` path, use `--first-parent` to show only what would actually be rewritten:
   ```
   git log --first-parent <dest_branch>..HEAD --format=%H %an <%ae>
   ```

### 6. Reviewer prompt — `zbobr/src/init.rs`

Add guidance to `REVIEWER_PROMPT`:

> When classifying commits as agent vs user: commits whose full hashes appear in ANY `Commits:` field anywhere in the task context (across all stages and all retry attempts) are known agent and system commits. Commits absent from ALL such lists are likely user-introduced and should be accepted as-is without questioning them.

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext`; update all construction sites |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL`; `commits` in `MdStage`; Display (full SHAs in persisted path, abbreviated in prompt-only path); from_str; from/into_stage_context; prompt-mode skip fix |
| `zbobr-utility/src/lib.rs` | Add `capture_git_head`; add `collect_agent_commits` returning `Result`; update `rewrite_authors_on_worktree` to take `commits: &[String]` with conditional env-filter |
| `zbobr-dispatcher/src/cli.rs` | Per-attempt baseline capture; retry-path: collect → conditionally rewrite (fatal) → post-rewrite re-collect → store; thread `attempt_baseline` through `finalize_stage_session` → `perform_stash_and_push`; `perform_stash_and_push`: collect pre-commits → rewrite; post-finalization re-collect and store |
| `zbobr/src/commands.rs` | `overwrite_author`: `collect_agent_commits` before rewrite; pass set to `rewrite_authors_on_worktree`; dry-run uses `--first-parent` |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` |

---

## Key Design Decisions

**Why post-rewrite re-collection?**
`git filter-branch` rewrites commit objects; their SHAs change. Storing pre-rewrite SHAs makes the stage record invalid. Re-collecting from the same `attempt_baseline` with `--first-parent` after rewrite returns the post-rewrite SHAs, which are the actual commits in the branch.

**Why full SHAs in persisted markdown?**
The GitHub task backend persists context as markdown (via `serialize_context`) and re-parses it (via `parse_context`). Abbreviated hashes in normal serialization would permanently replace full SHA identity on the first round-trip. Full SHAs in normal serialization, abbreviation only in prompt-mode rendering (which is never re-parsed), avoids this loss.

**Why `collect_agent_commits` returns `Result`?**
This function now defines the rewrite boundary and the reviewer's commit classification. Silent empty-set degradation would silently skip rewriting or produce empty commit records, making the feature's correctness contract fragile. Returning `Result` and using `?` in critical paths makes failures visible. Warn-and-empty is still appropriate at capture-time (baseline capture) and at post-finalization record-keeping, where the operation has already succeeded.

**Why conditional env-filter (not revised range)?**
`--first-parent` is a traversal constraint, not expressible as a revision range. `filter-branch` visits all commits in `<baseline>..HEAD`, but the conditional env-filter only rewrites commits in the pre-collected set. Second-parent user commits in the same range are visited but NOT rewritten because they are not in the set.

**Why `capture_git_head` and `collect_agent_commits` in `zbobr-utility`?**
Both the dispatcher and the CLI command need them. `zbobr-utility` is a shared dependency of both; centralizing them prevents divergent implementations.

**Why store commits on retry path even when `overwrite_author` is false?**
The `Commits:` field in context is used for reviewer prompt classification, which is independent of author rewriting. All stages must record their commits.

---

## Verification

1. `cargo build` — verify all call sites for changed function signatures compile.
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Round-trip: `StageContext` with full SHAs → serialized markdown → parsed → equal (full SHAs preserved).
   - Backward compat: no `Commits:` line parses to empty `commits`.
   - Prompt rendering: abbreviated SHAs shown; stage with commits but no records is NOT skipped.
3. Unit test for `rewrite_authors_on_worktree`: empty `commits` slice → returns `Ok(())` without running any git command.
4. Build verification: ensure all `StageContext { ... }` sites compile with the new `commits` field.

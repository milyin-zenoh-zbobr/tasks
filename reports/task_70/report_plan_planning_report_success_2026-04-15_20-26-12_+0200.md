# Plan v23: Show Commits in Context (Issue #314)

## Context

Issue #314 requires recording per-stage agent commits in `StageContext` so that:
1. Reviewer prompts can show which commits were made by agents vs. users.
2. The `overwrite_author` command rewrites only agent-made commits, not user commits.

Plans v11–v22 converged on the core architecture. Plan v22 was blocked by two issues (ctx_rec_44):

1. **Post-rewrite `collect_merge_commits(pre_update_head..HEAD)` is not stable after filter-branch.**
   `pre_update_head` is a stage commit SHA in the filter-branch range, so it gets rewritten and becomes invalid as a post-rewrite lower bound.

2. **Full SHAs in persist-mode violates the issue's "short hashes available both to user and prompt" contract.**
   The user-visible context (`serialize_context(..., false, ...)`) must also show abbreviated SHAs.

Plan v23 resolves both issues while preserving all other v22 decisions.

---

## Key Design Decisions (v23 changes from v22)

### Fix 1: Count-based post-rewrite collection (replaces `pre_update_head` boundary)

`commit_baseline` is the exclusive lower bound for `filter-branch` and is never rewritten — it is always a valid boundary in the post-rewrite history.

After `filter-branch`, `collect_agent_commits(commit_baseline..HEAD)` returns all commits in the stage range with post-rewrite SHAs, newest-first. This includes:
- Case A (fast-forward sync): `[ff_K, ..., ff_1, agent_N, ..., agent_1]` — K remote commits at the front, then N agent commits
- Case B (merge sync): `[merge, agent_N, ..., agent_1]` — sync merge commit at front, then N agent commits

To isolate stage commits, skip the first `ff_count = total - N - M` entries, where:
- `N = pre_commits.len()` (agent commits collected before `update_worktree`)
- `M = sync_commits.len()` (sync merge commits collected after `update_worktree`, before rewrite)
- `total = all_after_rewrite.len()`

This formula works for both cases:
- Case A: `ff_count = (N + K) - N - 0 = K` → skip K remote commits, keep N agent commits ✓
- Case B: `ff_count = (N + M) - N - M = 0` → keep all N+M commits ✓

Fast-forward and merge-commit sync are mutually exclusive per `git merge` semantics.

### Fix 2: Abbreviated SHAs everywhere (single representation)

Store 12-char abbreviated SHAs in `StageContext.commits`. Both persist-mode (user-visible) and prompt-mode render the same abbreviated format, satisfying the issue's "short hashes available both to user and prompt" requirement.

`rewrite_authors_on_worktree` env-filter uses shell prefix matching:
```sh
AGENT_COMMITS="<abbrev1> <abbrev2> ..."
found=0
for prefix in $AGENT_COMMITS; do
  case "$GIT_COMMIT" in "${prefix}"*) found=1; break;; esac
done
[ "$found" = "1" ] && export GIT_AUTHOR_NAME="..." && export GIT_AUTHOR_EMAIL="..." && export GIT_COMMITTER_NAME="..." && export GIT_COMMITTER_EMAIL="..."
```

12-char prefixes are safe for uniqueness (git recommends 7+ chars).

---

## Changes

### 1. Domain model — `zbobr-api/src/task.rs`

Add to `StageContext`:
```rust
#[serde(default, skip_serializing_if = "Vec::is_empty")]
pub commits: Vec<String>,
```
Update all `StageContext { ... }` construction sites to include `commits: Vec::new()`.

### 2. Utility functions — `zbobr-utility/src/lib.rs`

**Add `check_worktree_presence`**:
- Runs `git rev-parse --is-inside-work-tree` with stdout+stderr captured.
- Returns `Ok(true)` on success.
- Returns `Ok(false)` only when stderr contains "not a git repository".
- Returns `Err(...)` for any other non-zero exit.
- Replaces the silent `.is_ok()` pattern in `perform_stash_and_push`.

**Add `capture_git_head`**:
- Runs `git rev-parse HEAD`, returns the trimmed full SHA string (used only internally as pre-update bookmark — never stored).

**Add `collect_agent_commits`**:
- Runs `git log --first-parent --format=%.12H <lower_bound>..HEAD` (12-char abbreviated).
- Returns empty `Vec` if `lower_bound` is empty.

**Add `collect_merge_commits`**:
- Runs `git log --first-parent --merges --format=%.12H <lower_bound>..HEAD` (12-char abbreviated).
- Returns only commits with 2+ parents.
- Returns empty `Vec` if `lower_bound` is empty.

**Update `rewrite_authors_on_worktree` signature**:
```rust
pub async fn rewrite_authors_on_worktree(
    work_dir: &Path,
    lower_bound: &str,       // filter-branch scope: <lower_bound>..HEAD
    commits: &[String],      // 12-char abbreviated SHAs — only these get rewritten
    git_user_name: &str,
    git_user_email: &str,
) -> Result<()>
```
- If `commits.is_empty()` → return `Ok(())` immediately.
- Build `<lower_bound>..HEAD` as filter-branch scope.
- `--env-filter` script uses shell `for` + `case` prefix matching against `commits`.

### 3. Markdown serialization — `zbobr-api/src/context/mod.rs`

- Add `const COMMITS_LABEL: &str = "Commits"`.
- Add `commits: Vec<String>` to `MdStage` struct.
- `MdStage::from_stage_context`: `commits: stage.commits.clone()`.
- `MdStage::into_stage_context`: `commits: self.commits`.
- **Both persist-mode and prompt-mode**: emit abbreviated SHAs (backtick-wrapped) when `commits` is non-empty:
  `  Commits: \`<abbrev1>\` \`<abbrev2>\`` (indented 2 spaces, under the stage header)
- `from_str` parsing: detect `Commits:` lines, parse backtick-wrapped tokens.
- `Display` for `MdStage`: emit `Commits:` line after all records.
- Prompt-mode stage-skip condition: stage with commits but no records is NOT skipped.

### 4. Core logic — `zbobr-dispatcher/src/cli.rs`

#### `perform_stash_and_push` — revised sequence

New signature (add `commit_baseline: &str`):

Revised sequence:

1. Replace `.is_ok()` check with `zbobr_utility::check_worktree_presence(work_dir).await?`.
2. Stash (existing logic, gated on `is_git_repo`).
3. Pre-sync: `pre_commits = collect_agent_commits(work_dir, commit_baseline)` + `store_commits_to_task` (warn-and-continue).
4. Record `pre_update_head = capture_git_head(work_dir)` (internal only, not stored).
5. First `update_worktree`.
6. Post-sync: `sync_commits = collect_merge_commits(work_dir, &pre_update_head)` + store `dedup([pre_commits, sync_commits])` (warn-and-continue).
7. If `overwrite_author && is_uptodate && is_git_repo && !pre_commits.is_empty()`:
   a. `rewrite_authors_on_worktree(work_dir, commit_baseline, &pre_commits, ...)` — fatal.
   b. **Count-based post-rewrite re-collection** (v23 fix):
      ```
      N = pre_commits.len(); M = sync_commits.len()
      all = collect_agent_commits(work_dir, commit_baseline) — fatal
      ff_count = all.len().saturating_sub(N + M)
      final_commits = all.into_iter().skip(ff_count).collect()
      store_commits_to_task(self, task_id, final_commits) — non-fatal
      ```
   c. Second `update_worktree`.

#### `store_commits_to_task` (new non-fatal helper)

Modifies `task.context.stages.last_mut().commits`; logs warning on failure.

#### `finalize_stage_session`

Add `commit_baseline: &str` parameter, thread through to all three `perform_stash_and_push` call sites.

#### `CliStageRunner::run` — per-attempt baseline capture

Before `execute_tool`: capture `attempt_baseline = capture_git_head(&work_dir)`.

Retry path (before `continue`): collect pre_commits, optionally rewrite + re-collect, store.
Thread `attempt_baseline` to `finalize_stage_session`.

### 5. CLI command — `zbobr/src/commands.rs`

`overwrite_author`: replace fresh `collect_agent_commits(dest_branch)` with:
```rust
let agent_commits: Vec<String> = task.context.stages.iter()
    .flat_map(|s| s.commits.iter().cloned())
    .collect::<std::collections::HashSet<_>>()
    .into_iter().collect();
```
Pass to `rewrite_authors_on_worktree` (prefix matching handles abbreviated SHAs).

### 6. Reviewer prompt — `zbobr/src/init.rs`

Add 12-char prefix matching guidance to `REVIEWER_PROMPT`.

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext` |
| `zbobr-api/src/context/mod.rs` | Commits serialization; same abbreviated format for both modes |
| `zbobr-utility/src/lib.rs` | Add 4 new functions; update `rewrite_authors_on_worktree` |
| `zbobr-dispatcher/src/cli.rs` | Full `perform_stash_and_push` rewrite with count-based post-rewrite collection |
| `zbobr/src/commands.rs` | Use stored commits in `overwrite_author` |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` |

---

## Verification

1. `cargo build` — verify all changed function signatures compile.
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Round-trip with abbreviated SHAs; both persist and prompt modes render identically.
   - Missing `Commits:` parses to empty `commits`.
   - Stage with commits but no records not skipped in prompt-mode.
3. Unit test: `rewrite_authors_on_worktree` with empty `commits` → `Ok(())`, no git.
4. Unit tests: `check_worktree_presence` for git/non-git/error cases.
5. Unit test: `collect_merge_commits` excludes single-parent commits.
6. Verify count-based logic: N pre-commits, M sync-commits → skip `total-N-M` entries → correct stage commits for both ff and merge cases.
7. All `StageContext { ... }` construction sites include `commits: Vec::new()`.
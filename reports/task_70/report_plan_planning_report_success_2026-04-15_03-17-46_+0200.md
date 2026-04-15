# Plan: Show Commits in Context (Issue #314) — v8 (Final)

## Context

Reviewers need to distinguish between commits made by the agent during a stage and commits pushed by the user via GitHub. This plan adds per-attempt commit attribution to `StageContext` by capturing a local git baseline before each agent run.

Two previous blocking issues (ctx_rec_12) are addressed:
1. **Use local `HEAD` as baseline** instead of `origin/<work_branch>..HEAD` — works on both GitHub and FS backends without any remote sync assumptions.
2. **Per-attempt semantics** — baseline is captured once per retry-loop iteration (before the agent runs), passed to `finalize_stage_session`, and stored in the StageContext for that specific attempt.

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

Update the `StageContext { ... }` push site in `cli.rs` (line 545-557) to include `commits: Vec::new()`.

---

### 2. Markdown serialization — `zbobr-api/src/context/mod.rs`

**2a.** Add `commits: Vec<String>` to `MdStage` struct (line 363).

**2b.** `MdStage::Display` (line 370): after records loop, if `commits` is non-empty emit:
```
  Commits: `abc1234` `def5678`
```
Use a `const COMMITS_LABEL: &str = "Commits"` at module level (prevents label divergence between serializer and parser). Emit in both prompt and non-prompt mode.

**2c.** `MdContext::from_str` parse path (line 550): add detection between the `MdRecord::try_parse` check (line 569) and the `"- "` stage-title check (line 579). Parse backtick-wrapped tokens into `stage.commits`. This is the ONLY real parse path — `MdStage::from_str` is not called during context deserialization.

**2d.** `MdStage::from_stage_context` (line 446): add `commits: stage.commits.clone()`.

**2e.** `MdStage::into_stage_context` (line 486): add `commits: self.commits`.

**2f.** Prompt-mode inclusion fix in `MdContext::from_task_context` (line 651):
- Old: `if for_prompt && md_stage.records.is_empty() { continue; }`
- New: `if for_prompt && md_stage.records.is_empty() && md_stage.commits.is_empty() { continue; }`

---

### 3. Commit capture — `zbobr-dispatcher/src/cli.rs`

#### 3a. Per-attempt baseline capture

At the **start of each retry-loop iteration**, BEFORE `execute_tool()` runs (right after the `StageContext` is pushed at line 561), capture:

```rust
let commit_baseline = capture_git_head(&work_dir).await;
```

`capture_git_head` is a private async helper that runs `git rev-parse HEAD` and returns the SHA string, or `""` on failure.

Why this placement:
- `work_dir` is already set up (established before the loop at line 430-437)
- Agent has NOT run yet — no commits exist between this capture and the agent starting
- User commits cannot arrive until `perform_stash_and_push` merges them (happens in `finalize_stage_session`)
- Works for BOTH backends: GitHub backend merges user commits in Phase 8 of `perform_stash_and_push`; FS backend never merges user commits into the local worktree at all

#### 3b. Pass baseline to `finalize_stage_session`

Add `commit_baseline: String` parameter to `finalize_stage_session` (line 1994). The call site at line 681-691 passes `commit_baseline`.

#### 3c. Collect and record commits in `finalize_stage_session`

At the start of `finalize_stage_session`, before any `perform_stash_and_push` call:

```rust
let agent_commits = collect_agent_commits(work_dir, &commit_baseline).await;
```

`collect_agent_commits` helper runs `git log --format=%h <baseline>..HEAD` and returns list of short SHAs, or empty vec on failure/empty baseline.

After each successful `perform_stash_and_push` (all three outcome paths), record commits via `task_session.modify_task` writing to `stages.last_mut().commits`. Log warn on failure, never propagate.

`stages.last_mut()` is correct and unambiguous: it points to the `StageContext` pushed at the start of THIS iteration.

#### 3d. Retry semantics

When `outcome.execution_failed && attempts_remaining > 0`, the loop `continue`s — no `finalize_stage_session` is called. The baseline for that iteration is discarded. Intermediate failed retries are provider-level failures (the agent did NOT run, no commits were made). Their StageContext entries correctly have empty `commits`. On the next iteration, a fresh baseline is captured.

#### 3e. Author-rewrite note

`rewrite_authors_on_worktree` (called inside `perform_stash_and_push`) changes SHAs but not commit content. Hashes are captured BEFORE the call, so pre-rewrite SHAs are recorded. With default `overwrite_author = false`, this is a non-issue. With `overwrite_author = true`, captured SHAs differ from final pushed SHAs — acknowledged limitation, reflected in soft reviewer prompt language.

---

### 4. Reviewer prompt — `zbobr/src/init.rs`

Update step 5 in `REVIEWER_PROMPT` (around line 921):

Old: "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user according to the git history."

New: "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user. Commits listed under a stage's `Commits:` field in the task context are known agent commits; commits not listed there are likely user commits (attribution may be incomplete for stages where commit tracking was unavailable or where author rewriting was enabled)."

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext`; update all construction sites |
| `zbobr-api/src/context/mod.rs` | `COMMITS_LABEL` const; `commits` field in `MdStage`; serialize in `Display`; parse in `MdContext::from_str`; mapping in `from_stage_context`/`into_stage_context`; fix prompt-mode inclusion check |
| `zbobr-dispatcher/src/cli.rs` | `capture_git_head` helper; `collect_agent_commits` helper; capture baseline per-loop-iteration after StageContext push; add `commit_baseline` param to `finalize_stage_session`; record commits after push in all three outcome paths |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` step 5 |

---

## Verification

1. `cargo build` — no compile errors.
2. Unit tests in `zbobr-api/src/context/mod.rs`:
   - Roundtrip: `StageContext` with `commits` → serialize to markdown → parse back → equal commits.
   - Backward compat: empty `commits` produces no `Commits:` line; existing markdown without `Commits:` parses with empty commits.
   - Prompt inclusion: stage with commits and no records is NOT skipped in prompt mode.
3. Manual integration check: run a task stage, verify the resulting context markdown contains a `Commits:` line with correct short SHAs.

# Plan: Show Commits in Context (Issue #314)

## Goal
1. When a stage finishes, append the short commit hashes made during that stage to the stage's context entry. Both users and agents (e.g. the reviewer) can see these.
2. Update the reviewer prompt to clarify that "user commits" = commits whose hashes are **not** listed in any stage record in the context.

---

## Closest Analog

`MdStageTitle` in `zbobr-api/src/context/stage_title.rs` is the closest analog for the new commit-list serialization: it defines a special-purpose line with backtick-wrapped tokens and handles both `Display` (serialize) and `FromStr` (deserialize). The `try_parse_next_backtick` helper there is the parsing analog for extracting commit hashes.

For the runtime collection of commits, the analog is the `output_link` recording in `finalize_stage_session` (`zbobr-dispatcher/src/cli.rs`): after `perform_stash_and_push` succeeds, the function reads git state and updates the last `StageContext` via `modify_task`.

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

The field is `Vec<String>` of short git hashes (7-character abbreviated SHA). Default empty so existing data round-trips unchanged.

### 2. Markdown serialization — `zbobr-api/src/context/mod.rs`

**`MdStage` struct** — add `commits: Vec<String>`.

**Display (serialization)**: After writing records, if `commits` is non-empty, write a `Commits:` line:
```
  Commits: `abc1234` `def5678`
```
Two-space indent, matching non-checkbox records. Use a `const COMMITS_LABEL: &str = "Commits"` constant. This line is written in both prompt and non-prompt mode (agents need it to identify agent commits).

**FromStr (parsing)**: In the line loop, after the record/title detection, detect lines whose trimmed content starts with `"Commits: "`. Strip the prefix, then parse backtick-wrapped tokens reusing the `try_parse_next_backtick` helper (make it accessible or inline equivalent logic). Store in `commits`.

**`from_stage_context`**: Copy `stage.commits` → `md.commits`.

**`into_stage_context`**: Copy `md.commits` → `StageContext.commits`.

No changes to the prompt-mode rendering path (commits are shown in both modes).

### 3. Commit collection at stage end — `zbobr-dispatcher/src/cli.rs`

In `finalize_stage_session`, in the **success path** (after `perform_stash_and_push` succeeds and before computing the post-stage signal):

1. Run `git log --format=%h origin/<base_branch>..HEAD` to get all short hashes in the work branch ahead of base. Use `self.repo_backend().branch()` for the base branch name (same pattern as `perform_stash_and_push`).
2. From `task_session.get_task().await?`, collect all commits already recorded in **previous** stages (all entries except the last).
3. `new_commits` = all hashes not in the previously-recorded set.
4. If non-empty, call `task_session.modify_task` to set `stage.commits = new_commits` on the last stage.

This runs after `rewrite_authors_on_worktree` (called inside `perform_stash_and_push`), so the hashes captured are the final pushed hashes. The subtraction logic (`all - previously_recorded`) correctly identifies new commits per-stage.

Skip gracefully if the work directory is not a git repo or `git log` fails (log a warning but don't fail the stage).

Extract this logic into a small private async helper `collect_new_stage_commits(task_session, work_dir, base_branch) -> Vec<String>` to keep `finalize_stage_session` readable.

### 4. Prompt update — `zbobr/src/init.rs`

In `REVIEWER_PROMPT`, update step 5 from:
> "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user according to the git history."

To:
> "But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user. User commits are commits whose short hashes do **not** appear in any stage record in the task context; agent commits are explicitly listed there under each stage."

---

## Key Design Decisions

- **Commits are in `StageContext`, not `StageInfo`**: `StageInfo` is metadata about the stage execution (who ran it, when, with what model). Commits are output of the stage — same level as `records`.
- **Short (abbreviated) hashes**: Match the `--format=%h` git output. Long SHAs are overkill for human readability; the issue says "short pr hashes".
- **Subtract previously-recorded**: This is more robust than recording pre-stage HEAD, since the SHA of earlier commits can change under `overwrite_author`. After rewriting, the final `git log` reflects the canonical pushed SHAs.
- **Only success path**: Commit collection is done only when `perform_stash_and_push` succeeds in the normal (non-interrupted, non-errored) path. This keeps the logic minimal for the primary use case.
- **`COMMITS_LABEL` constant**: Prevents the string `"Commits"` from diverging between serializer and parser.
- **No new `TaskSession` method needed**: `modify_task` closure is sufficient; adding a dedicated method is not warranted for a one-liner field assignment.

---

## Files Changed

| File | Change |
|------|--------|
| `zbobr-api/src/task.rs` | Add `commits: Vec<String>` to `StageContext` |
| `zbobr-api/src/context/mod.rs` | Serialize/deserialize commits in `MdStage`; map through `from_stage_context`/`into_stage_context` |
| `zbobr-dispatcher/src/cli.rs` | Collect new commits after successful `perform_stash_and_push` in `finalize_stage_session` |
| `zbobr/src/init.rs` | Update `REVIEWER_PROMPT` step 5 to define "user commits" as commits not in stage context |

---

## Tests

- Unit test in `zbobr-api/src/context/mod.rs`: roundtrip serialize/deserialize a `StageContext` with non-empty `commits` — verify commits appear in markdown and parse back correctly.
- Unit test: verify commits do NOT appear in markdown when `commits` is empty (backward compat).
- The commit collection logic in `cli.rs` is integration-only (requires git); no new unit test needed there — existing integration tests cover the stage execution path.

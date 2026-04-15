I reviewed Plan v16 against the current code in `zbobr-dispatcher/src/cli.rs`, `zbobr-utility/src/lib.rs`, `zbobr/src/commands.rs`, `zbobr-api/src/context/mod.rs`, `zbobr-api/src/task.rs`, `zbobr-task-backend-github/src/separator.rs`, and `zbobr-repo-backend-github/src/github.rs`, plus issue #314.

The plan is materially better than v15: it correctly aligns author rewriting with an explicit first-parent-derived commit set instead of a plain revision range, and it brings the standalone `overwrite-author` command under the same detection model. That addresses the core cross-author safety concern from the latest user guidance.

However, I do **not** consider v16 implementation-ready yet. There are still blocking design gaps.

## Blocking issue 1: retry-path storage still uses pre-rewrite hashes

The new requirement was explicit:
1. determine stage commits
2. rewrite them if necessary
3. store them to the stage record

But the retry-path pseudocode in v16 still does this order:
- collect `retry_commits`
- call `rewrite_authors_on_worktree(..., &retry_commits, ...)`
- store `stage.commits = retry_commits`

That stores the **pre-rewrite** SHAs.

This is architecturally wrong because `git filter-branch` rewrites commit objects. Once a targeted commit changes author/committer metadata, its SHA changes; and descendants in the rewritten portion can change SHA as well because their parent IDs change. So the hashes stored in the stage record would no longer match the commits that actually exist after rewrite.

That breaks the whole purpose of the field:
- later prompt classification would treat stale hashes as agent commits,
- actual rewritten commits would be absent from the `Commits:` lists,
- future logic that depends on these recorded hashes would be working from invalid identifiers.

### Required revision
The plan needs to state explicitly that on any path where rewrite happens, commit storage must be based on a **post-rewrite re-collection** of the first-parent set, not the pre-rewrite input set.

Concretely, the retry path should be:
1. collect pre-rewrite commit set,
2. rewrite using that set,
3. collect again from `attempt_baseline..HEAD` with `--first-parent`,
4. store the post-rewrite SHAs into `stage.commits`.

The finalization path already moves in that direction by re-collecting after `finalize_stage_session`; the retry path must do the same.

## Blocking issue 2: abbreviated `Commits:` display is lossy in the GitHub-backed persistence model

Plan v16 proposes:
- store full SHAs in `StageContext.commits`,
- display abbreviated hashes in markdown for readability,
- parse them back and “store full SHA if full-length, otherwise store as-is”.

That is not safe in this codebase.

The task GitHub backend persists context by serializing it to markdown and later parsing it back:
- `zbobr-task-backend-github/src/separator.rs` uses `serialize_context(...)` when writing,
- the same file uses `parse_context(...)` when reading back,
- concurrent-update merge logic also reparses and reserializes the markdown context.

So the markdown representation is not just a UI view — it is the persistence format for at least one backend.

If normal non-prompt context output abbreviates SHAs, then a round-trip through GitHub storage will permanently replace the canonical full hashes with shortened ones. After that:
- commit matching becomes ambiguous,
- the rewrite mechanism can no longer safely compare against `$GIT_COMMIT` full SHAs,
- the “known agent commits” set in context is degraded over time.

This is a fundamental mismatch between the proposed representation and the current storage architecture.

### Required revision
The plan needs to preserve **full SHAs in the persisted, parseable context format**.

Sound options include:
1. emit full SHAs in normal context markdown and only abbreviate in prompt-only rendering, since prompt rendering is not reparsed, or
2. emit a lossless machine-readable representation in normal context and optionally add a human-friendly abbreviated view separately.

But a normal markdown `Commits:` line that serializes only abbreviated hashes is not acceptable for this repository.

## Blocking issue 3: `collect_agent_commits` cannot fail by warning-and-returning-empty in correctness-critical paths

Plan v16 defines `collect_agent_commits` as:
- `git log --first-parent --format=%H <lower_bound>..HEAD`
- on error: `tracing::warn!`, return `Vec::new()`

That is too weak for the role this function now plays.

After the latest requirement, this function is no longer a best-effort diagnostic helper. It is part of the correctness boundary for:
- deciding which commits may be author-rewritten,
- deciding which commits get recorded into the stage context,
- deciding which commits reviewers/prompt logic will classify as agent-owned.

If it silently degrades to an empty set, the system can:
- skip rewriting when rewriting was needed,
- write an empty `Commits:` field for a stage that actually made commits,
- later misclassify agent commits as user commits simply because detection failed once.

That is not a minor implementation detail; it undermines the feature’s contract.

### Required revision
The plan should make `collect_agent_commits` return `Result<Vec<String>>` and treat failures as fatal anywhere correctness depends on the result:
- retry-path rewrite/store,
- finalization-time rewrite/store,
- any other path that records `stage.commits`.

A warn-and-empty fallback is only defensible in clearly non-authoritative contexts such as an optional preview or dry-run display, not in the main rewrite/persist pipeline.

## Non-blocking observations

- The direction to move shared git helpers into `zbobr-utility` is good and matches the fact that both dispatcher and CLI need them.
- The prompt-mode inclusion fix in `zbobr-api/src/context/mod.rs` is necessary; today prompt rendering skips stages with no records.
- The first-parent assumption is consistent with the current `update_worktree()` implementation in `zbobr-repo-backend-github/src/github.rs`, which merges `origin/<work_branch>` and then the base branch into the local worktree.

## Conclusion

Plan v16 is closer, but it still leaves the implementation vulnerable in three core places:
1. retry-stage records would store stale pre-rewrite SHAs,
2. abbreviated markdown commits would corrupt canonical commit identity in the GitHub-backed persistence path,
3. commit detection is specified as best-effort even though it now defines rewrite and review correctness.

Those should be revised before implementation.
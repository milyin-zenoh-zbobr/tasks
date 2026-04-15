The plan has the right general direction, but it is not sound enough to implement as written.

## Blocking issues

1. **The markdown parsing change is aimed at the wrong place.**
   The plan says to teach `MdStage::from_str` in `zbobr-api/src/context/mod.rs` to parse a new `Commits:` line. But the real context parser does not use `MdStage::from_str` when deserializing a task context. `parse_context()` goes through `MdContext::from_str()`, which parses the document line-by-line and currently only accepts stage headers (`- ...`) and record lines; any other non-empty line becomes an error. A literal `Commits:` line would therefore still fail parsing unless `MdContext::from_str()` is updated as well (or the parser is refactored to route stage bodies through `MdStage::from_str`).

   Relevant code:
   - `zbobr-api/src/context/mod.rs:547-617` (`MdContext::from_str`)
   - `zbobr-api/src/context/mod.rs:714-716` (`parse_context`)
   - `zbobr-api/src/context/mod.rs:403-428` (`MdStage::from_str`, which is not the only parser path)

2. **The proposed commit-delta algorithm can misclassify user commits as agent commits.**
   The plan suggests: take `git log origin/<base_branch>..HEAD`, subtract hashes already recorded in previous stages, and attach the remainder to the current stage. That does not actually mean “commits made during this stage”. If the user makes a commit on the work branch between two agent stages, that commit is not in any previous stage record, so the next stage would record it as an agent commit. That breaks the issue’s core requirement, because the reviewer prompt will treat “not listed in context” as the definition of a user commit.

   This is especially important because the reviewer prompt already relies on distinguishing user-introduced history from agent-introduced history.

   A sounder design needs a **stage-start baseline**, not just subtraction against previously recorded stage output. For example, capture the branch-ahead count (or equivalent baseline) when the `StageContext` is created before execution, then after stash/push/rewrite compute only the newly added suffix for that stage. The current plan explicitly rejects a start-of-stage baseline, but without one it cannot reliably satisfy the issue.

   Relevant code:
   - `zbobr-dispatcher/src/cli.rs:532-560` (stage context is created before execution, so this is the natural place to capture baseline state)
   - `zbobr-dispatcher/src/cli.rs:1993-2062` (`finalize_stage_session` success path)
   - `zbobr-dispatcher/src/cli.rs:2115-2194` (`perform_stash_and_push`, including author rewrite)
   - `zbobr/src/init.rs:917-922` (reviewer prompt depends on distinguishing user changes)

## Important secondary concern

3. **Prompt visibility is not fully covered by the plan.**
   In prompt mode, `MdContext::from_task_context()` currently skips stages with no records: `if for_prompt && md_stage.records.is_empty() { continue; }` (`zbobr-api/src/context/mod.rs:648-655`). The plan says “no changes to the prompt-mode rendering path”, but that means a stage with commits and no records would still be omitted from prompts, violating the issue requirement that commit hashes be available to agents. The prompt-mode inclusion rule needs to account for commits too.

## Recommendation

Revise the plan before implementation:
1. Move the markdown parsing/design discussion to the actual parse path (`MdContext::from_str`) or explicitly refactor parsing so `MdStage::from_str` becomes authoritative.
2. Replace the “all commits ahead of base minus previously recorded hashes” approach with a true stage baseline captured at stage start, so inter-stage user commits are not attributed to the next agent stage.
3. Update prompt-mode inclusion criteria so stages with commits remain visible even if they have no context records.
4. Add at least one behavior-level test for prompt/context serialization with commits and one test for stage commit attribution logic; existing integration tests do not currently assert this feature.
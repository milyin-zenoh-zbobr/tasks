Plan v24 is ready. Here's a summary of what it resolves:

**Two blocking issues from v23 (ctx_rec_46):**

1. **`MdContext::from_str` state machine fix** — Plan v23 mentioned updating `MdStage::from_str` but the actual active parser is the line-by-line state machine in `MdContext::from_str` (line 610 bails on unrecognized lines). Plan v24 explicitly adds a `Commits:` handler before that `bail!`: detect `trimmed.starts_with("Commits:")` with an open stage, extract backtick-wrapped SHA tokens, extend `current_stage.commits`, and `continue`.

2. **Post-second-sync commit collection** — After `rewrite_authors_on_worktree`, `git filter-branch` rewrites local SHAs, so the second `update_worktree` can create a new merge commit. Plan v24 adds a step after the second sync: `collect_merge_commits(work_dir, &final_commits[0])` to pick up any new merge commit, then stores `post_sync_new + final_commits` as the complete set.
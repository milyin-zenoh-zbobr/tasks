Plan v22 addresses both blocking issues from v21:

**Issue 1 (fast-forward contamination)**: Replaced the post-sync `baseline..HEAD` re-collection with a targeted `collect_merge_commits` call using `git log --first-parent --merges`. This works because `update_worktree` either creates an actual merge commit (2+ parents, captured by `--merges`) or fast-forwards (no new commit created locally). Fast-forwarded external commits have only 1 parent and are excluded by the `--merges` filter — so they can never end up in the stage record.

**Issue 2 (hash contract inconsistency)**: Aligned the reviewer prompt guidance to match prompt-mode rendering. Prompt-mode emits abbreviated 12-char SHAs; the reviewer prompt now says to match by "first 12 chars" prefix — fully consistent.
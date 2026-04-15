I’m pulling the final plan and checking the actual code paths it relies on before judging whether it’s implementation-ready.

● Search (grep)
  │ "stage context|StageContext|context prompt|reviewer prompt|commits" in **/*.{rs,md,toml}
  └ 71 lines found

● Get issue details (MCP: github-mcp-server) · owner: "milyin", repo: "zbobr", issue_number: 314, m…
  └ {"number":314,"title":"remember commits made by agents","body":"- When stage ...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_11"
  └ # Plan: Show Commits in Context (Issue #314) — Final (v6)

I’ve got the plan; now I’m validating the exact parser, prompt, and stage-finalization paths it names so I can judge whether the proposed design actually fits the code.

● Read task.rs
  │ zbobr-api/src/task.rs
  └ L170:215 (46 lines read)

● Read init.rs
  │ zbobr/src/init.rs
  └ L900:940 (40 lines read)

● Read fs.rs
  │ zbobr-repo-backend-fs/src/fs.rs
  └ L130:210 (81 lines read)

● Read github.rs
  │ zbobr-repo-backend-github/src/github.rs
  └ L760:860 (101 lines read)

● Read mod.rs
  │ zbobr-api/src/context/mod.rs
  └ L340:710 (371 lines read)

● Read cli.rs
  │ zbobr-dispatcher/src/cli.rs
  └ L500:660 (161 lines read)

● Read cli.rs
  │ zbobr-dispatcher/src/cli.rs
  └ L1960:2075 (116 lines read)

I’ve confirmed the parser and prompt paths the plan names. I’m now checking the git/push flow and every `StageContext` constructor to see whether the plan underestimates the implementation surface or misses backend-specific behavior.

● Search (grep)
  │ "overwrite_author|rewrite_authors_on_worktree|perform_stash_and_push|git_output\(|git_check\("
  │ (./zbobr-dispatcher/src/cli.rs)
  └ 9 lines found

● Search (grep)
  │ "StageContext \{" in **/*.rs
  └ 33 lines found

● Read github.rs
  │ zbobr-repo-backend-github/src/github.rs
  └ L858:945 (88 lines read)

● Read lib.rs
  │ zbobr-utility/src/lib.rs
  └ L300:365 (66 lines read)

● Read cli.rs
  │ zbobr-dispatcher/src/cli.rs
  └ L2075:2215 (141 lines read)

I found a likely weak point around provider retries, so I’m checking the prior review and the retry flow to see whether the final plan truly fixes that or still collapses multiple attempts into one context entry.

● Read cli.rs
  │ zbobr-dispatcher/src/cli.rs
  └ L430:710 (281 lines read)

● Search (grep)
  │ "finalize_stage_session\(|execute_stage_session\(|execution_failed"
  │ (./zbobr-dispatcher/src/cli.rs)
  └ 8 lines found

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_10"
  └ The latest plan is **closer**, and its main GitHub-side correction is sound: ...

I found one backend-level concern already. I’m fetching the earlier retry-attribution critique too, because the current plan’s “record on `last_mut()` at finalization” still looks like it may lump multiple provider attempts into one stage entry.

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_8"
  └ The revised plan fixes several earlier issues: it targets the real markdown p...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_6"
  └ The revised plan fixes several earlier problems: it targets the real parse pa...

I’ve confirmed the retry concern isn’t about missing commits entirely anymore; it’s about where they get attributed. I’m checking one more thing that could be more serious: whether the plan’s pre-push hashes survive the author-rewrite path at all.

● Read README.md
  └ L1:220 (220 lines read)

● Read mod.rs
  │ zbobr-api/src/config/mod.rs
  └ L720:780 (61 lines read)

● Search (grep)
  │ "overwrite_author" in **/*.{rs,toml,md}
  └ 7 lines found

● report_failure (MCP: zbobr) · brief: "Plan is close, but not implementation-ready: commit attribu…
  └ Report stored

--- stderr ---

Changes   +0 -0
Requests  1 Premium (3m 53s)
Tokens    ↑ 308.1k • ↓ 7.0k • 238.5k (cached) • 4.2k (reasoning)
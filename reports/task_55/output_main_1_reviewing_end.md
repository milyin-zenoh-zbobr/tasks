I’m pulling the plan, worker report, and branch diff first so I can review the full implementation against the intended analog and checklist.

● Show branch commits and changed files (shell)
  │ git --no-pager log --oneline origin/main..HEAD && printf '\n---DIFF---\n' && git --no-pager diff
  │ --stat origin/main...HEAD && printf '\n---FILES---\n' && git --no-pager diff --name-only
  │ origin/main...HEAD
  └ 24 lines...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_4"
  └ # Updated Plan: prompts-should-be-hash

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_10"
  └ # Plan: prompts-should-be-hash

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_11"
  └ # Implementation: prompts-should-be-hash

I’ve got the intended design. Now I’m reading the actual code changes and the surrounding config patterns to check for consistency and any gaps.

● Read init.rs
  │ zbobr/src/init.rs
  └ L1:260 (260 lines read)

● Read prompts.rs
  │ zbobr-dispatcher/src/prompts.rs
  └ L1:320 (319 lines read)

● Read mod.rs
  │ zbobr-api/src/config/mod.rs
  └ L1:420 (420 lines read)

● Show patch for changed files (shell)
  │ git --no-pager diff origin/main...HEAD -- zbobr-api/src/config/mod.rs
  │ zbobr-dispatcher/src/prompts.rs zbobr/src/init.rs zbobr-dispatcher/src/cli.rs
  │ zbobr-dispatcher/src/lib.rs zbobr-dispatcher/src/workflow.rs
  │ zbobr-dispatcher/tests/mcp_integration/abstract_test_helpers.rs
  └ 18 lines...

● Read mod.rs
  │ zbobr-api/src/config/mod.rs
  └ L420:860 (441 lines read)

● Read lib.rs
  │ zbobr-dispatcher/src/lib.rs
  └ L1:200 (200 lines read)

● Read abstract_test_helpers.rs
  │ zbobr-dispatcher/tests/mcp_integration/abstract_test_helpers.rs
  └ L1:220 (220 lines read)

● Read workflow.rs
  │ zbobr-dispatcher/src/workflow.rs
  └ L1:220 (220 lines read)

● Read cli.rs
  │ zbobr-dispatcher/src/cli.rs
  └ L1:220 (220 lines read)

● Search (grep)
  │ "pub prompts: Option<IndexMap<String, TomlOption<PathBuf>>>|pub prompts_dir:
  │ Option<PathBuf>|impl zbobr_utility::MergeToml for WorkflowConfig|impl WorkflowConfig|struct
  │ WorkflowToml|fn try_into_config" (zbobr-api/src/config/mod.rs)
  └ 8 lines found

● Search (grep)
  │ "prompt_files_for_stage|merge_prompt_maps|prompts = \{|role_prompt|prompt:
  │ TomlOption|role_def\.prompt|stage_def\.prompts" in **/*.{rs,toml}
  └ 41 lines found

I’ve narrowed it to the prompt merge and config resolution paths plus the test coverage around them. Next I’m checking whether the implementation matches the planned inheritance semantics in edge cases.

● Read prompts.rs
  │ zbobr-dispatcher/src/prompts.rs
  └ L880:1060 (152 lines read)

● Read init.rs
  │ zbobr/src/init.rs
  └ L450:660 (211 lines read)

● Read init.rs
  │ zbobr/src/init.rs
  └ L1200:1255 (56 lines read)

● Read cli.rs
  │ zbobr-dispatcher/src/cli.rs
  └ L1100:1165 (66 lines read)

● Read mod.rs
  │ zbobr-api/src/config/mod.rs
  └ L2380:2605 (225 lines read)

● Show focused diffs for key files (shell)
  │ git --no-pager diff origin/main...HEAD -- zbobr-api/src/config/mod.rs | sed -n '1,260p' &&
  │ printf '\n---PROMPTS-DIFF---\n' && git --no-pager diff origin/main...HEAD --
  │ zbobr-dispatcher/src/prompts.rs | sed -n '1,260p' && printf '\n---INIT-DIFF---\n' && git
  │ --no-pager diff origin/main...HEAD -- zbobr/src/init.rs | sed -n '1,260p'
  └ 18 lines...

● Search (grep)
  │ "role_prompt|prompt_files_for_stage\(|prompts: Vec<PathBuf>|prompt: TomlOption<PathBuf>" in
  │ **/*.rs
  └ 20 lines found

● Inspect base branch analog for prompts (shell)
  │ git --no-pager show origin/main:zbobr-dispatcher/src/prompts.rs | sed -n '180,260p' && printf
  │ '\n---CONFIG---\n' && git --no-pager show origin/main:zbobr-api/src/config/mod.rs | sed -n
  │ '40,120p;220,280p;426,580p' && printf '\n---INIT---\n' && git --no-pager show
  │ origin/main:zbobr/src/init.rs | sed -n '450,640p'
  └ 574 lines...

I found one substantive regression in the new prompt-slot implementation: prompt composition order is no longer stable, and in the default workflow it is now reversed relative to the old `role_prompt + prompts` behavior.

● report_failure (MCP: zbobr) · brief: "Review failed: prompt-slot merge reorders prompts and defau…
  └ Report stored

**Review failed:** the hash-based prompt implementation introduces a prompt-order regression. The merge logic reorders overridden `IndexMap` keys, and the new default workflow now resolves prompts as `task.md` before `<role>.md`, reversing the old behavior where the role’s main prompt came first.

The key issue is the `shift_remove() + insert()` pattern in both `zbobr-api/src/config/mod.rs` and `zbobr-dispatcher/src/prompts.rs`: overriding an inherited slot moves it to the end. Combined with `zbobr/src/init.rs` only seeding the workflow-level `task` slot, the default prompt order is now wrong for normal stages.

--- stderr ---

Total usage est:        1 Premium request
API time spent:         1m 41s
Total session time:     2m 1s
Total code changes:     +0 -0
Breakdown by AI model:
 gpt-5.4                  302.3k in, 5.3k out, 242.4k cached (Est. 1 Premium request)
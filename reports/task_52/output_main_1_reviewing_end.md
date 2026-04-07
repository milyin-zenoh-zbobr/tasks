I’m pulling the task context and the full branch diff first so I can review the implementation against the plan and checklist, then I’ll inspect the touched code for consistency and gaps.

● Get branch commits and changed files (shell)
  │ git --no-pager log --oneline origin/main..HEAD && printf '\n---DIFF---\n' && git --no-pager diff
  │ --stat origin/main...HEAD && printf '\n---FILES---\n' && git --no-pager diff --name-only
  │ origin/main...HEAD
  └ 16 lines...

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_1"
  └ ## Plan: Update Commands (issue #318)

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_3"
  └ ## What

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_2"
  └ ## What

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_5"
  └ ## Implementation Summary

● get_ctx_rec (MCP: zbobr) · id: "ctx_rec_4"
  └ ## Plan Summary

I’ve got the plan and the touched files. Next I’m reading the exact edits and nearby analog code so I can judge whether the implementation matches the intended patterns and whether anything subtle was missed.

● Read commands.rs
  │ zbobr/src/commands.rs
  └ 1 line read

● Read main.rs
  │ zbobr/src/main.rs
  └ L1:260 (260 lines read)

● Read cli.rs
  │ zbobr-dispatcher/src/cli.rs
  └ L1:320 (320 lines read)

● Show full task diff (shell)
  │ git --no-pager diff origin/main...HEAD -- zbobr/src/commands.rs zbobr/src/main.rs
  │ zbobr-dispatcher/src/cli.rs
  └ 339 lines...

I’ve isolated the main edits. I’m now checking surrounding code paths and other references to make sure the new CLI shapes are consistent everywhere and didn’t leave behind mismatched assumptions.

● Read commands.rs
  │ zbobr/src/commands.rs
  └ L70:190 (121 lines read)

● Read commands.rs
  │ zbobr/src/commands.rs
  └ L320:410 (91 lines read)

● Read main.rs
  │ zbobr/src/main.rs
  └ L250:340 (35 lines read)

● Read cli.rs
  │ zbobr-dispatcher/src/cli.rs
  └ L1140:1188 (49 lines read)

● Read cli.rs
  │ zbobr-dispatcher/src/cli.rs
  └ L2280:2335 (48 lines read)

● Search (grep)
  │ "task list --select|task select|TaskSubcommand::Select|select: bool|--logs" in **/*.{rs,md,toml}
  └ 24 lines found

I found a likely regression in the new `--logs` handling, and I’m checking whether it’s just a test gap or an actual parser bug in the hoisting logic.

● Read main.rs
  │ zbobr/src/main.rs
  └ L40:66 (26 lines read)

● Read cli.rs
  │ zbobr-dispatcher/src/cli.rs
  └ L188:230 (43 lines read)

● Search (grep)
  │ "parse_cli\(|GlobalArgs::augment_args|require_equals = true|default_missing_value =
  │ "true"|num_args = 0..=1" in **/*.rs
  └ 9 lines found

● report_failure (MCP: zbobr) · brief: "Found a correctness regression in the new `--logs` parsing:…
  └ Report stored

**Review failed:** the `task select` change looks consistent, but the new `--logs` implementation has a real parsing regression.

The main issue is in `zbobr-dispatcher/src/cli.rs`: the optional-value hoisting for `--logs` consumes **any** following non-flag token, not just `true`/`false`. That can steal positional arguments from subcommands, and combined with `logs: Vec<String>` plus `resolve_logs()` in `zbobr/src/main.rs`, it also accepts invalid values like `--logs=maybe` as `true`. There’s a second inconsistency too: `require_equals = true` means `--logs false` is only normalized in the post-subcommand hoisting path, so the advertised space-separated form is not handled consistently when `--logs` appears before the subcommand.

--- stderr ---

Total usage est:        1 Premium request
API time spent:         1m 31s
Total session time:     1m 46s
Total code changes:     +0 -0
Breakdown by AI model:
 gpt-5.4                  186.6k in, 4.3k out, 149.9k cached (Est. 1 Premium request)
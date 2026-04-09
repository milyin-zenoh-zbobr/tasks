# Plan: Print Reports to Stdout (issue #316)

## Problem
When agents call MCP report tools (`report_success`, `report_failure`, `report_intermediate`, `stop_with_question`, `stop_with_error`), their content is stored in GitHub and logged via `tracing::info!` — but **nothing is printed to stdout**. Operators running the zbobr CLI see no visible output from agent reports without checking logs or running `task show`.

## Proposed Change

**Single file**: `zbobr-dispatcher/src/mcp/traits.rs`

1. **`report_impl`** (line 72): After successfully adding the context record, add a `println!` call that prints the tool name and `brief` to stdout, e.g.:
   ```
   [report_success] <brief>
   [report_intermediate] <brief>
   ```

2. **`pause_with_status_impl`** (line 350): After setting the pause status, add a `println!` call that prints the tool name and `message` to stdout, e.g.:
   ```
   [stop_with_question] <message>
   [stop_with_error] <message>
   ```

These `println!` calls go at the success path, alongside the existing `log_mcp_string_response` tracing calls.

## No Other Files Need Changing
The `print_task` function in `cli.rs` (which already handles `task show`) does not need to be changed; the task is only about live stdout output during stage execution.

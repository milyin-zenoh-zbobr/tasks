## Implementation Summary

### Change 1: `task select` subcommand (commit 6affd943)

**Files modified:**
- `zbobr/src/commands.rs` — Added `Select` variant to `TaskSubcommand` enum (no arguments). Removed `select: bool` from `List` variant. Added new `Select` handler with the same ready-task selection logic previously in the `List` handler.
- `zbobr-dispatcher/src/cli.rs` — Updated comment at line ~1156 from `task list --select` to `task select`.
- `zbobr/src/main.rs` — Added `task_select_parses_without_arguments` and `task_list_no_longer_accepts_select_flag` tests.

`task process --select` was left unchanged as the issue only targets `task list --select`.

### Change 2: `--logs` optional boolean with last-value-wins (commit 9c5fe5f8)

**Files modified:**
- `zbobr/src/main.rs` — Changed `logs: bool` to `logs: Vec<String>` with `#[arg(long, num_args = 0..=1, default_missing_value = "true", require_equals = true, action = clap::ArgAction::Append)]`. Added `resolve_logs()` helper that takes the last value and defaults to `false` if empty. Updated usage and added comprehensive tests.
- `zbobr-dispatcher/src/cli.rs` — Changed `GlobalArgs.logs` type to match. Updated hoisting logic with `ArgValence` enum (Flag/RequiredValue/OptionalValue) to correctly handle optional-value args. The hoister joins optional values with `=` for clap compatibility with `require_equals = true`.

**Supported forms:** `--logs`, `--logs=true`, `--logs=false`, and space-separated `--logs true`/`--logs false` (via hoisting logic). Multiple occurrences use last-value-wins.

### Testing
- All 26 zbobr tests pass (22 pre-existing + 4 new).
- Pre-existing compilation errors in `zbobr-dispatcher` test files (unrelated type mismatches in `task.rs`) prevent running dispatcher tests, but these errors exist on the base branch too.
- Clean `cargo build` succeeds.
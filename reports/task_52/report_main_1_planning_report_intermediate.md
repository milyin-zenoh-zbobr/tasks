## Plan: Update Commands (issue #318)

### Context
The issue requests two CLI improvements:
1. Replace `task list --select` flag with a dedicated `task select` subcommand
2. Make `--logs` accept an optional boolean parameter (`--logs`, `--logs true`, `--logs false`, `--logs=false`) with last-value-wins when specified multiple times

### Change 1: `task select` subcommand

**Files affected:**
- `zbobr/src/commands.rs` — CLI types and handler
- `zbobr/src/main.rs` — tests
- `zbobr-dispatcher/src/cli.rs` — comment referencing `task list --select`

**Approach:**
- Add a new `Select` variant to `TaskSubcommand` enum (no arguments needed — it inherits the same behavior as the current `--select` flag on `List`)
- Move the select logic from the `List` handler into a new `Select` match arm
- Remove the `select: bool` field from `List` variant
- `task process --select` remains unchanged (issue only mentions `task list --select`)
- Update existing tests in `main.rs` to reflect the change; add a test for `task select`
- Update the comment in `cli.rs:1384` to reference `task select` instead of `task list --select`

**Analog:** The existing `TaskSubcommand` variants (e.g., `Show`, `Delete`) serve as the pattern for adding a new variant.

### Change 2: `--logs` optional boolean with last-value-wins

**Files affected:**
- `zbobr/src/main.rs` — `Cli` struct and logs initialization
- `zbobr-dispatcher/src/cli.rs` — `GlobalArgs` struct and hoisting logic in `parse_cli`
- `zbobr/src/main.rs` — tests for `--logs`

**Approach:**
- Change `logs: bool` (with `ArgAction::SetTrue`) to a type that supports optional boolean values with multiple occurrences. Use `Vec<String>` with `#[arg(long, num_args = 0..=1, default_missing_value = "true", action = clap::ArgAction::Append)]` or similar clap configuration. Take the last value, default to `false` if empty.
- Update the hoisting logic in `parse_cli`: currently it classifies args as either "takes value" or "doesn't take value". For `--logs` with optional value (`num_args = 0..=1`), the hoister needs to handle the case where the next argument may or may not be a value. The hoister should check whether the next arg is a valid boolean string ("true"/"false") before consuming it as a value for `--logs`.
- Update the `GlobalArgs` struct in `cli.rs` to match the new type
- Update `main.rs` to extract the final bool from the collected values
- Add a helper function (e.g., `resolve_logs`) to determine the final logs value from the collected args
- Update tests: `logs_flag_defaults_to_false`, `logs_flag_parses_when_present`, add tests for `--logs false`, `--logs true`, `--logs --logs false` (last wins = false)

**Key risk:** The `parse_cli` hoisting logic needs careful attention. The current `takes_value` detection uses `a.get_action()` to classify flags. With `Append` action, `--logs` would be classified as "takes value", but since the value is optional, the hoister must not blindly consume the next argument. The hoister should inspect `num_args` metadata or check if the next token is a valid boolean before hoisting it alongside `--logs`.

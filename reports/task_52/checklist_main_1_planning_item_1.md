## What
Change the `--logs` flag from a simple boolean (`ArgAction::SetTrue`) to an optional-value flag that accepts `--logs`, `--logs true`, `--logs false`, `--logs=true`, `--logs=false`, with last-value-wins when specified multiple times.

## Why
Issue #318 requests this so users can explicitly disable logs with `--logs false` and override earlier flags (e.g., in shell aliases) with last-value-wins behavior.

## Details

### CLI struct changes
- In `main.rs` (`Cli` struct): Change `logs: bool` to a type that collects multiple occurrences. Use `Vec<String>` with clap attributes like `#[arg(long, num_args = 0..=1, default_missing_value = "true", action = clap::ArgAction::Append)]`. Add a helper to resolve the final boolean: take the last value, default to `false` if empty.
- In `zbobr-dispatcher/src/cli.rs` (`GlobalArgs` struct): Change `pub logs: bool` to match the new type from `Cli`.

### Hoisting logic in `parse_cli` (cli.rs ~line 117-200)
This is the KEY RISK AREA. The hoisting logic currently classifies args as either "takes value" or "doesn't take value" using `get_action()`. With `Append` action and `num_args = 0..=1`, `--logs` becomes an optional-value flag. The hoister must NOT blindly consume the next argument as a value for `--logs` — it should check whether the next token is a valid boolean string (`"true"`/`"false"`) before treating it as a value. If the next token is not a boolean, hoist only `--logs` itself (which will use the `default_missing_value`).

### Tests
- Update existing tests: `logs_flag_defaults_to_false`, `logs_flag_parses_when_present`
- Add new tests: `--logs false` (explicit false), `--logs true` (explicit true), `--logs --logs false` (last wins = false), `--logs=false` (equals syntax)

## Analog
Look at how other flags with optional values or `Append` action are handled in the codebase, if any. Otherwise follow standard clap patterns for optional-value flags.
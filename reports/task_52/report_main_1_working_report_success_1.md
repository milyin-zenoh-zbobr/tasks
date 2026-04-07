## Changes made

### Fix 1: Hoister only consumes valid boolean tokens (cli.rs:217-225)
Changed the `OptionalValue` branch in the post-subcommand hoisting path from `!raw_args[i + 1].starts_with('-')` to `is_bool_literal(&raw_args[i + 1])`. This prevents `--logs` from stealing positional arguments like `42` in `task show --logs 42`.

### Fix 2: Pre-subcommand normalization (cli.rs:170-192)
Added OptionalValue handling in the pre-subcommand path. Previously, `--logs false` before a subcommand was pushed as two separate tokens, which clap (with `require_equals = true`) couldn't parse. Now it's normalized to `--logs=false` when followed by a valid boolean literal.

Added a helper function `is_bool_literal()` that checks for case-insensitive "true"/"false".

### Fix 3: Type safety with Vec<bool> (main.rs + cli.rs)
Changed the `logs` field from `Vec<String>` to `Vec<bool>` in both `Cli` and `GlobalArgs`. This makes clap reject invalid values like `--logs=maybe` at parse time. Simplified `resolve_logs` to just `values.last().copied().unwrap_or(false)`.

### Tests
- All 27 existing tests pass
- Added `logs_invalid_value_rejected` test verifying `--logs=maybe` is rejected

### Commits
1. `f2065df7` — Fix --logs parsing: validate boolean tokens and use Vec<bool>
2. `6d01ebe1` — Add test for --logs rejecting invalid boolean values
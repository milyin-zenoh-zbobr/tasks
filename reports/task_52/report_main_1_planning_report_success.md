## Plan Summary

Two changes per issue #318:

### Change 1: `task select` subcommand
- Add `Select` variant to `TaskSubcommand` enum in `commands.rs`
- Remove `select: bool` from `List` variant, move logic to new `Select` handler
- Update comment in `cli.rs` referencing old flag
- Update and add tests in `main.rs`

### Change 2: `--logs` optional boolean with last-value-wins
- Change `logs: bool` to `Vec<String>` with `Append` action and `num_args = 0..=1` in both `Cli` (main.rs) and `GlobalArgs` (cli.rs)
- Key risk: hoisting logic in `parse_cli` must handle optional-value detection — check if next token is valid boolean before consuming
- Add resolver helper for final boolean value
- Comprehensive test coverage for all combinations

### Design decisions
- `task process --select` is left unchanged (issue only targets `task list --select`)
- Chose `Vec<String>` + Append over other approaches for clean last-value-wins semantics
- Hoister needs boolean-token detection to avoid consuming unrelated arguments
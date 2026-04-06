## What
Add a new `Select` variant to the `TaskSubcommand` enum in `commands.rs` that replaces the `select: bool` field currently on the `List` variant. The `task process --select` flag is unrelated and must remain unchanged.

## Why
Issue #318 requests replacing `task list --select` with a dedicated `task select` subcommand for better CLI ergonomics.

## Details
- In `commands.rs`: Add a `Select` variant to `TaskSubcommand` (no arguments needed). Remove the `select: bool` field from the `List` variant. Add a handler for `Select` in the match arm — move the existing select logic from the `List` handler.
- In `zbobr-dispatcher/src/cli.rs` line ~1156: Update the comment that references `task list --select` to say `task select` instead.
- In `main.rs`: Update existing tests that use `task list --select` to use `task select`. Add a new test for the `task select` subcommand.

## Analog
Follow the pattern of existing `TaskSubcommand` variants like `Show` and `Delete` for how to add the new variant and its handler.
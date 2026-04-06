Plan is ready for review. Two checklist items have been created:

1. **Add `task select` subcommand** — new `Select` variant in `TaskSubcommand`, remove `--select` from `task list`, update tests and comments
2. **Make `--logs` accept optional boolean** — `Vec<String>` with `Append` action, hoisting logic update for optional values, last-value-wins resolution, comprehensive tests
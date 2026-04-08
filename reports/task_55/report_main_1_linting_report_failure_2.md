Formatting/linting run summary:

Commands executed:
- cargo fmt --all -- --check
- cargo clippy --all-targets --all-features -- -D warnings

Captured output (truncated preview):

Running: cargo fmt --all -- --check
Diff in /data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr/src/commands.rs:3:
 use std::{path::PathBuf, sync::Arc};
 
 use clap::Subcommand;
-use zbobr_api::{Pipeline, Stage, WorktreeBackend, config::{Role, StageDefinition, WorkflowConfig}};
+use zbobr_api::{
+    Pipeline, Stage, WorktreeBackend,
+    config::{Role, StageDefinition, WorkflowConfig},
+};
 ...

(Full output saved to /tmp/copilot-tool-output-1775649311025-me5lig.txt on the runner.)

Notes:
- cargo fmt reported many diffs across multiple source files (formatting required).
- cargo clippy output was included in the captured output; inspect the saved file for details.

Recommendations:
- Run `cargo fmt --all` to apply formatting changes.
- Run `cargo clippy --all-targets --all-features` and address any warnings/errors.


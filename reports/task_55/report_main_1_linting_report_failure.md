Commands executed:
- cargo fmt -- --check
- cargo clippy --all-targets --all-features -- -D warnings

Results summary:
- cargo fmt -- --check produced diffs (formatting not compliant). See snippet below.
- cargo clippy output not captured (/tmp/lint_clippy.txt missing). Clippy may not have completed or produced no output.

Formatter diff (excerpt from /tmp/lint_fmt.txt):
Diff in /data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr/src/commands.rs:3:
 use std::{path::PathBuf, sync::Arc};
 
 use clap::Subcommand;
-use zbobr_api::{Pipeline, Stage, WorktreeBackend, config::{Role, StageDefinition, WorkflowConfig}};
+use zbobr_api::{
+    Pipeline, Stage, WorktreeBackend,
+    config::{Role, StageDefinition, WorkflowConfig},
+};
 use zbobr_dispatcher::{
     ConfiguredPromptBuilder, TaskDir, TaskListEntry, VAR_DESTINATION_BRANC

(Full formatter output saved to /tmp/lint_fmt.txt on runner.)

Next steps:
- Run `cargo fmt` to apply formatting fixes.
- Re-run `cargo fmt -- --check` and `cargo clippy ...` to verify.

Full raw outputs (if needed) are available in /tmp/lint_fmt.txt and /tmp/lint_clippy.txt on the runner environment.
=== cargo fmt -- --check ===
Diff in zbobr/src/commands.rs:3:
 use std::{path::PathBuf, sync::Arc};
 
 use clap::Subcommand;
-use zbobr_api::{Pipeline, Stage, WorktreeBackend, config::{Role, StageDefinition, WorkflowConfig}};
+use zbobr_api::{
+    Pipeline, Stage, WorktreeBackend,
+    config::{Role, StageDefinition, WorkflowConfig},
+};
 ... [multiple diffs omitted for brevity]
=== END fmt ===

=== cargo clippy (workspace, all-targets, all-features, -D warnings) ===
error: this `impl` can be derived
  --> zbobr-utility/src/toml_option.rs:28:1
   |
28 | / impl<T> Default for TomlOption<T> {
29 | |     fn default() -> Self {
30 | |         Self::Absent
31 | |     }
32 | | }
   | |_^
   |
   = help: for further information visit https://rust-lang.github.io/rust-clippy/rust-1.94.0/index.html#derivable_impls
   = note: `-D clippy::derivable-impls` implied by `-D warnings`
   = help: to override `-D warnings` add `#[allow(clippy::derivable_impls)]`
help: replace the manual implementation with a derive attribute and mark the default variant
   |
19 + #[derive(Default)]
20 | pub enum TomlOption<T> {
21 |     /// Field was not present in the TOML source.
22 ~     #[default]
23 ~     Absent,
   |

Build failed: could not compile `zbobr-utility` due to the clippy error above.

Full logs were captured when running the checks; run the same commands locally to reproduce:
  - cargo fmt -- --check
  - cargo clippy --workspace --all-targets --all-features -- -D warnings

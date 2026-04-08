Commands executed:
1) cargo fmt --all -- --check
2) cargo clippy --workspace --all-targets --all-features -- -D warnings

cargo fmt --all -- --check output (summary/diffs):
Diff in zbobr-macros/src/lib.rs: changed import ordering and formatting
Diff in zbobr/src/init.rs: collapsed chained field access into single line
Diff in zbobr-repo-backend-github/src/github.rs: JSON formatting in ResponseTemplate::new(...).set_body_json(...) differs in several test locations
Diff in zbobr-task-backend-github/src/github.rs: wrapped chrono::Local::now() formatting across lines
Diff in zbobr-task-backend-github/src/github.rs (tests): assert_eq! formatting changed to multi-line

(Full cargo-fmt diffs captured in earlier run; examples shown above.)

cargo clippy --workspace --all-targets --all-features -- -D warnings output (failing errors):
error: this `if` statement can be collapsed
  --> zbobr-utility/src/toml_edit_util.rs:49:5
   |
49 |     if let Some(Item::Table(parent_table)) = doc.get_mut(parent_table_name) {
50 |         if let Some(Item::Table(child_table)) = parent_table.get_mut(child_key) {
51 |             child_table.set_dotted(true);
52 |         }
53 |     }
   |
   = help: collapse nested if block

error: this `impl` can be derived
  --> zbobr-utility/src/toml_option.rs:28:1
   |
28 | impl<T> Default for TomlOption<T> {
29 |     fn default() -> Self {
30 |         Self::Absent
31 |     }
32 | }
   |
   = help: replace with #[derive(Default)] and mark variant with #[default]

Result: formatting check failed (cargo fmt produced diffs) and clippy failed with errors (warnings treated as errors). Please run `cargo fmt` to apply formatting changes and fix or allow the clippy suggestions (or run clippy without -D warnings to review warnings). Provide guidance if automatic fixes are desired.

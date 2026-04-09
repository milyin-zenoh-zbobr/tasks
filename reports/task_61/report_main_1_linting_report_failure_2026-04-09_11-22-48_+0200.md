Commands run:
 1) cargo fmt --all -- --check
 2) cargo clippy --all-targets --all-features -- -D warnings

Result: Formatting check failed (cargo fmt reported diffs). Clippy produced warnings (see clippy_output.txt).

Files with formatting diffs (extracted from cargo fmt output):
- zbobr-macros/src/lib.rs
- zbobr/src/init.rs
- zbobr-api/src/config/mod.rs
- zbobr-dispatcher/src/cli.rs
- zbobr-dispatcher/src/lib.rs
- zbobr-dispatcher/src/prompts.rs
- zbobr-dispatcher/src/workflow.rs
- zbobr-dispatcher/tests/mcp_integration/abstract_test_helpers.rs
- zbobr-repo-backend-github/src/github.rs
- zbobr-task-backend-github/src/github.rs
- zbobr-utility/src/lib.rs
(and many more; cargo fmt output saved to /tmp/copilot-tool-output-1775726537634-ds73wh.txt)

Sample clippy warnings (from clippy_output.txt):
- many `if` statements can be collapsed (e.g. zbobr-api/src/config.rs:218, 228, 238, ...)
- `zbobr-api` generated 8 warnings; other crates generated warnings as well

Full cargo fmt+clippy run output saved: /tmp/copilot-tool-output-1775726537634-ds73wh.txt
Full clippy output in repository: clippy_output.txt

Action: report_failure because formatting check failed; developer should run `cargo fmt --all` to apply formatting changes and re-run `cargo fmt -- --check` and `cargo clippy --all-targets --all-features -- -D warnings` to verify the linter cleanly passes.
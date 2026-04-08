# Formatting and Linting Fixes

## Summary
All formatting and linting issues have been successfully fixed. Both `cargo fmt --check` and `cargo clippy --all-targets --all-features -- -D warnings` now pass cleanly.

## Changes Made

### 1. Formatting Fixes Applied
- Applied all rustfmt changes to ensure consistent code style
- Fixed line wrapping and import ordering across multiple files

### 2. Clippy Fixes

#### Derivable Impl (zbobr-utility/src/toml_option.rs)
- **Issue**: Manual Default impl for TomlOption<T> that could be derived
- **Fix**: Added `#[derive(Default)]` and `#[default]` attribute to Absent variant, removed manual implementation
- **Lines**: 18-32

#### Collapsible If Statements
- **zbobr-utility/src/toml_edit_util.rs:49** - Collapsed nested if-let using `&&` operator
- **zbobr/src/init.rs:676** - Collapsed nested if-let using `&&` operator

#### Needless Borrows
- **zbobr-api/src/config/mod.rs:931** - Removed unnecessary `ref` in pattern `ref tool`
- **zbobr-api/src/config/mod.rs:972** - Removed unnecessary `ref` in pattern `ref parent_name`
- **zbobr-repo-backend-github/src/github.rs:1249, 1298, 1347** - Removed unnecessary borrowing in `.base_uri()` calls (3 occurrences)

#### Useless Conversions (Same-Type)
- **zbobr-utility/src/toml_option.rs** - Derived Default impl
- **zbobr-api/src/config/mod.rs** - Removed useless `.into()` calls on Option<i32>
- **zbobr-dispatcher/src/prompts.rs:137** - Removed useless `.into()` from Some(String).into()
- **zbobr-dispatcher/src/lib.rs** - Removed useless `.into()` conversions:
  - Lines 598, 620, 783 - String to String conversions on provider keys
  - Lines 728, 950 - Option<i32> to Option<i32> conversions
- **zbobr-dispatcher/src/task.rs:949, 1021, 1086** - Removed useless `.into()` from Option<String> conversions
- **zbobr-dispatcher/tests/mcp_integration/abstract_test_helpers.rs:794** - Removed useless `.into()` from Option<StageTransition>

### 3. Config Structure Fix
- **zbobr/src/init.rs:354-359** - Added missing `auto_sync_fork: TomlOption::Value(true)` field to ZbobrRepoBackendGithubToml struct initializer (required by recent schema changes)

## Verification
- `cargo fmt --all -- --check` ✓ Passed
- `cargo clippy --all-targets --all-features -- -D warnings` ✓ Passed

All code now adheres to Rust formatting standards and clippy lint rules.
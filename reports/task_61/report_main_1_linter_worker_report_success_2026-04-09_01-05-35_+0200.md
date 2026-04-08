## Summary

Successfully fixed all formatting and linting issues identified in the sync fork task.

## Changes Made

### Formatting Issues Fixed
1. **zbobr-macros/src/lib.rs:7** - Alphabetically sorted imports in use statements
2. **zbobr/src/init.rs:1120** - Reformatted line wrapping for consistency
3. **zbobr-repo-backend-github/src/github.rs** - Multiple serde_json! macro formatting fixes
4. **zbobr-task-backend-github/src/github.rs** - Formatting updates for consistency

### Clippy Linting Issues Fixed

**zbobr-utility:**
- **toml_edit_util.rs:49** - Collapsed nested if statements using `&&` operator
- **toml_option.rs:28** - Derived Default trait instead of manual implementation

**zbobr-api:**
- **config/mod.rs:931** - Removed unnecessary reference in `let Some(ref tool)` pattern
- **config/mod.rs:972** - Removed unnecessary reference in `let Some(ref parent_name)` pattern
- **config/mod.rs:1696, 2626, 2651** - Removed useless `.into()` conversions from Option values

**zbobr-repo-backend-github:**
- **github.rs:1249, 1298, 1347** - Removed unnecessary borrow references in `.base_uri()` calls

**zbobr-dispatcher:**
- **prompts.rs:137** - Removed useless `.into()` conversion
- **lib.rs:300** - Removed useless `.into()` conversion
- **task.rs:949, 1021, 1086** - Removed useless `.into()` conversions (3 instances)
- **lib.rs:598, 620, 783, 939, 940** - Removed useless `.into()` conversions for string type conversions
- **lib.rs:728, 950** - Removed useless `.into()` conversions from Option values

**zbobr (main binary):**
- **init.rs:354** - Added missing `auto_sync_fork` field to ZbobrRepoBackendGithubToml constructor
- **init.rs:676** - Collapsed nested if statements using `&&` operator

**zbobr-dispatcher tests:**
- **abstract_test_helpers.rs:794** - Removed useless `.into()` conversion from StageTransition

## Verification

Both checks now pass cleanly:
- ✅ `cargo fmt --all -- --check` - No formatting differences
- ✅ `cargo clippy --all-targets --all-features -- -D warnings` - No warnings or errors

All changes maintain the original functionality while improving code quality and consistency.
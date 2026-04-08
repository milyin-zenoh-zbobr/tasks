## Summary
Successfully fixed all formatting and linting issues in the prompts-should-be-hash implementation.

## Issues Fixed

### 1. Formatting Issues (cargo fmt)
Fixed formatting in multiple files to conform to Rust style guidelines:
- `zbobr/src/commands.rs`: Restructured long import statements
- `zbobr/src/init.rs`: Formatting adjustments

### 2. Clippy Errors

#### zbobr-utility/src/toml_option.rs
- **Issue**: Manual `Default` impl for `TomlOption<T>` enum (derivable_impls)
- **Fix**: Added `#[derive(Default)]` and marked `Absent` variant with `#[default]`
- **Result**: Removed manual impl block

#### zbobr-api/src/config/mod.rs
- **Issue**: Needless borrows in pattern matching (3 instances)
  - Line 933: `&& let Some(ref tool)` → `&& let Some(tool)`
  - Line 974: `if let Some(ref parent_name)` → `if let Some(parent_name)`
- **Issue**: Useless conversions (3 instances)
  - Lines 1697, 2627, 2652: `Some(X).into()` → `Some(X)` (removing unnecessary conversions)

#### zbobr-dispatcher/src/lib.rs
- **Issue**: Useless conversions (6 instances)
  - Lines 598, 620, 783, 939, 940: `"x".to_string().into()` → `"x".to_string()`
  - Lines 728, 950: `Some(X).into()` → `Some(X)`

#### zbobr-dispatcher/src/prompts.rs
- **Issue**: Useless conversion (1 instance)
  - Line 137: `Some(Executor::CLAUDE.to_string()).into()` → `Some(Executor::CLAUDE.to_string())`

#### zbobr-dispatcher/src/task.rs
- **Issue**: Useless conversions (3 instances)
  - Lines 949, 1021, 1086: `Some("copilot".to_string()).into()` → `Some("copilot".to_string())`

#### zbobr-dispatcher/tests/mcp_integration/abstract_test_helpers.rs
- **Issue**: Useless conversion (1 instance)
  - Line 794: `Some(StageTransition::pause()).into()` → `Some(StageTransition::pause())`

## Verification
- ✅ `cargo fmt -- --check` passes (no formatting issues)
- ✅ `cargo clippy --workspace --all-targets --all-features -- -D warnings` passes (no clippy errors)
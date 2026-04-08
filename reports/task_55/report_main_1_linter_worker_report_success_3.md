## Formatting and Linting Fixes

Successfully fixed all formatting and linting issues in the prompts-should-be-hash implementation. 

### Issues Fixed

1. **zbobr-utility/src/toml_option.rs**: Derived `Default` trait for `TomlOption<T>` enum to eliminate manual implementation, marking `Absent` variant with `#[default]` attribute. This fixed clippy's `derivable_impls` warning.

2. **zbobr-api/src/config/mod.rs**:
   - Removed unnecessary `ref` binding in pattern match for `role_def.tool.as_option()` (lines 931-935), changed from `ref tool` with `(*tool).clone()` to just `tool` with `tool.clone()`.
   - Removed unnecessary `ref` binding for `def.parent.as_option()` match (lines 974-975), simplifying dereference pattern.
   - Removed useless `.into()` conversions for `ToolEntry` priority field (which is `Option<i32>`): changed `Some(5).into()` to `Some(5)` in test code (lines 1697, 2627, 2652).

3. **zbobr-dispatcher/src/prompts.rs**: 
   - Removed useless `.into()` on `tool` field for `StageInfo` (line 137, which is `Option<String>`).
   - Fixed Tool construction patterns: replaced `"name".to_string().into()` with `"name".into()` for cleaner API usage (multiple test locations).

4. **zbobr-dispatcher/src/lib.rs**:
   - Removed useless `.into()` on `executor.access_key` field (line 299, which is `Option<Secret>`).
   - Fixed Tool construction patterns throughout test code.
   - Removed useless `.into()` conversions for `ToolEntry` priority field (lines 725, 944).

5. **zbobr-dispatcher/src/task.rs**: Removed useless `.into()` conversions on `tool` field for `StageInfo` instances (lines 949, 1021, 1086, which is `Option<String>`).

6. **zbobr-dispatcher/tests/mcp_integration/abstract_test_helpers.rs**: Removed useless `.into()` conversion on `on_success` field (line 794, which is `Option<StageTransition>`).

### Verification

- ✅ `cargo fmt --all -- --check` passes - no formatting issues
- ✅ `cargo clippy --all-targets --all-features -- -D warnings` passes - no linting warnings or errors
- All 385+ build targets compile successfully without warnings

The changes are purely cleanup fixes that don't alter functionality - they remove unnecessary type conversions and derive attributes where appropriate.
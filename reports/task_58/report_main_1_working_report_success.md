# Task Complete: NaN values in config (Issue #332)

## Summary

All 5 implementation steps for `TomlOption<T>` are complete across 4 commits on `zbobr_fix-58-nan-values-in-config`.

## What Was Done

### Commit 1: Create `TomlOption<T>` enum in `zbobr-utility`
- `zbobr-utility/src/toml_option.rs`: Full three-state enum (`Absent`, `ExplicitNone`, `Value(T)`) with serde support (TOML `nan` literal → `ExplicitNone`), `merge()`, `as_option()`, `into_option()`, `From<Option<T>>`, `MergeToml` impl, and comprehensive tests.

### Commit 2: Update `config_struct` proc macro
- `zbobr-macros/src/lib.rs`: Changed generated `*Toml` struct fields from `Option<T>` to `TomlOption<T>` and updated `MergeToml` impl to call `.merge()`.

### Commit 3: Update manually-defined config types
- `zbobr-api/src/config/mod.rs`: Changed `RoleDefinition`, `StageDefinition`, `ProviderDefinition` fields to `TomlOption<T>`; updated `MergeToml` impls; fixed `resolve_tool()`/`resolve_single_provider()` consumers.

### Commit 4: Fix consumer code + add tests
- Fixed all struct literals, pattern matches, and field access across 10 files in `zbobr-dispatcher`, `zbobr-api`, and `zbobr` crates.
- Added integration tests:
  - `nan_in_toml_clears_base_config_value`: parses TOML with `nan`, merges, verifies `ExplicitNone` and priority survival
  - `nan_in_toml_stage_field_clears_inherited_role`: verifies stage role cleared by `nan` overlay
  - `merge_toml_trait`: verifies MergeToml trait delegation
- All tests pass (340 total, excluding 3 pre-existing `zbobr-task-backend-github` failures unrelated to this change).

## Files Changed
- `zbobr-utility/src/toml_option.rs`
- `zbobr-utility/src/lib.rs`
- `zbobr-macros/src/lib.rs`
- `zbobr-api/src/config/mod.rs`
- `zbobr-dispatcher/src/lib.rs`
- `zbobr-dispatcher/src/prompts.rs`
- `zbobr-dispatcher/src/workflow.rs`
- `zbobr-dispatcher/src/task.rs`
- `zbobr-dispatcher/src/cli.rs`
- `zbobr-dispatcher/tests/integration_github_github.rs`
- `zbobr-dispatcher/tests/mcp_integration/abstract_test_helpers.rs`
- `zbobr-dispatcher/tests/mcp_integration/env.rs`
- `zbobr/src/init.rs`

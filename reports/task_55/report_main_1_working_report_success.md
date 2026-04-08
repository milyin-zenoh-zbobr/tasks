# Implementation: prompts-should-be-hash

## Summary

Replaced the old `prompt: TomlOption<PathBuf>` (RoleDefinition), `role_prompt: TomlOption<PathBuf>` + `prompts: Option<Vec<PathBuf>>` (StageDefinition) fields with a unified `prompts: Option<IndexMap<String, TomlOption<PathBuf>>>` field at all three config levels (workflow, role, stage).

## Changes

### zbobr-api/src/config/mod.rs
- Added `merge_prompt_maps()` helper for per-key TomlOption merge semantics
- `RoleDefinition`: replaced `prompt: TomlOption<PathBuf>` with `prompts: Option<IndexMap<String, TomlOption<PathBuf>>>`
- `StageDefinition`: replaced `role_prompt: TomlOption<PathBuf>` + `prompts: Option<Vec<PathBuf>>` with `prompts: Option<IndexMap<String, TomlOption<PathBuf>>>`
- `WorkflowConfig` + `WorkflowToml`: added `prompts: Option<IndexMap<String, TomlOption<PathBuf>>>`
- Updated `resolve_paths()`, `merge_toml()`, `try_into_config()`, and `Config::build()` for all structs
- Updated all tests to use new format

### zbobr-dispatcher/src/prompts.rs
- Rewrote `prompt_files_for_stage()` to perform three-level merge (workflow → role → stage) using per-key TomlOption semantics, filtering ExplicitNone slots, collecting Value paths in insertion order
- Updated all tests

### zbobr-dispatcher/src/cli.rs, workflow.rs, lib.rs, tests/
- Fixed remaining references to old field names

### zbobr/src/init.rs
- Updated `default_workflow()`: workflow-level `prompts = { task: task.md }`, each role has `prompts = { main: <role>.md }`, stages no longer carry per-stage prompts (inherited from workflow)
- Updated test `all_default_workflow_role_prompts_are_registered`

## Test Results
All 138 unit tests in zbobr-api + all other crate tests pass.

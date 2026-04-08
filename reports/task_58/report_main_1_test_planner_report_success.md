# Test Plan: NaN values in config (Issue #332)

## Summary
The implementation is well-tested for the core TomlOption types and the three primary consumer paths. Four gaps were identified, each with a checklist item.

## Existing coverage (no additional tests needed)
- `TomlOption<T>` unit tests: full 9-combination merge matrix, serde roundtrips (nan↔ExplicitNone, absent, value), all conversions and helpers
- Consumer layer ExplicitNone semantics: `resolve_tool`, `resolve_single_provider` (all 4 fields), `prompt_files_for_stage` (all 3 TomlOption variants)
- TOML-level integration: `nan_in_toml_clears_base_config_value`, `nan_in_toml_stage_field_clears_inherited_role`

## Gaps → Checklist items

### [ctx_rec_16] prompt_files_for_stage — role-level prompt ExplicitNone
Tests the uncovered path in `prompt_files_for_stage`: `stage.role_prompt = Absent` + `role_def.prompt = ExplicitNone` → empty result. The existing test suite covers the Absent-inherits-from-role case only when role.prompt is a Value.

### [ctx_rec_17] Stage transition fields cleared by nan
`StageDefinition.on_success/on_failure/on_intermediate/on_no_report` are now `TomlOption<StageTransition>` but no test verifies that `on_success = nan` in a TOML overlay parses as ExplicitNone, wins over the base Value during merge, and produces `None` from `on_success()`.

### [ctx_rec_18] WorkflowToml.prompts_dir = nan
`WorkflowToml.prompts_dir` is now `TomlOption<PathBuf>` with no ExplicitNone-specific tests. Tests needed: overlay nan clears the base value; `try_into_config()` converts ExplicitNone → None.

### [ctx_rec_19] config_struct macro-generated Toml struct nan handling
The macro now generates `TomlOption<T>` for non-map fields. No tests exist for the macro's generated code path specifically. Tests in one of the executor crates (`ZbobrExecutorClaudeToml`) should verify nan deserialization and merge for a macro-generated struct.

## What was explicitly NOT added
- Tests asserting on static prompt text or config literal values (per guidelines)
- Tests for ExplicitNone on `parent` field (no inheritance chain for parent resolution, already covered by validate)
- Snapshot tests for the macro expansion itself (too brittle)

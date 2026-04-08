# Fix: ExplicitNone semantics in consumer layer (review feedback)

## Problem
The review found that `ExplicitNone` was being collapsed to `None` too early in three consumer paths, making `nan` in config behave the same as an absent field (silently inheriting parent values).

## Changes

### `zbobr-api/src/config/mod.rs`

**`resolve_tool()`**: Replaced `if let Some(ref tool) = stage_def.tool.as_option()` with a `match` on `stage_def.tool`:
- `Value(tool)` → return the tool
- `ExplicitNone` → bail with error (inheritance blocked)
- `Absent` → fall through to role-level tool

**`resolve_single_provider()`**: Replaced `into_option().unwrap_or(parent.xxx)` patterns with per-field `match` blocks:
- `executor = ExplicitNone` → error (executor is required)
- `priority = ExplicitNone` → reset to default (10)
- `plan_mode = ExplicitNone` → reset to default (false)
- `access_key = ExplicitNone` → `None` (clears parent's access_key)

**New behavior tests added:**
- `resolve_tool_stage_explicit_none_blocks_role_fallback`
- `resolve_providers_child_clears_access_key_with_explicit_none`
- `resolve_providers_child_clears_priority_with_explicit_none`
- `resolve_providers_child_clears_plan_mode_with_explicit_none`
- `resolve_providers_child_executor_nan_is_error`

### `zbobr-dispatcher/src/prompts.rs`

**`prompt_files_for_stage()`**: Replaced `if let Some(ref main) = stage_def.role_prompt.as_option()` with a `match` on `stage_def.role_prompt`:
- `Value(main)` → push the path
- `ExplicitNone` → do nothing (inheritance blocked)
- `Absent` → fall through to role-level prompt

Also added `use zbobr_utility::TomlOption` import and explicit type annotation `|p: PathBuf|` to resolve type inference issue introduced by the match change.

**New behavior tests added:**
- `prompt_files_for_stage_absent_role_prompt_inherits_role_level`
- `prompt_files_for_stage_explicit_none_blocks_role_fallback`
- `prompt_files_for_stage_value_overrides_role_level`

## Test results
- 133 tests pass in `zbobr-api`
- 97 tests pass in `zbobr-dispatcher` (unit tests)
- 3 pre-existing failures in `zbobr-task-backend-github` (crypto provider issue unrelated to this change)
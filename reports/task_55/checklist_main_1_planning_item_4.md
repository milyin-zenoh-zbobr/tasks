## Test updates

**File**: `zbobr-api/src/config/mod.rs` (tests section)

Tests to update or replace:
- `role_definition_resolve_paths_makes_prompt_absolute()` — change from `prompt: TomlOption::Value(path)` to `prompts: Some(IndexMap::from([("main", TomlOption::Value(path))]))`
- `role_definition_resolve_paths_preserves_absolute()` — same
- `stage_definition_resolve_paths_resolves_all_prompt_fields()` — was testing `role_prompt` + `prompts` Vec, replace with single `prompts` IndexMap
- `pipeline_config_resolve_paths_resolves_stage_prompts()` — same
- `workflow_toml_resolve_paths_resolves_nested_prompt_fields()` — update for new structure
- `workflow_toml_merge_preserves_resolved_paths()` — update for new structure
- `workflow_toml_merge_roles_key_wise()` — check if it tests prompt fields

New tests to add:
- Three-level prompt merge: workflow has `{ task: "task.md" }`, role has `{ main: "planner.md" }`, stage has `{ task: nan }` → result is only `["planner.md"]`
- Role prompt override: role has `{ main: "planner.md" }`, stage has `{ main: "override.md" }` → result is `["override.md"]`
- NaN clearing in prompts map: base has `{ main: "role.md", task: "task.md" }`, overlay has `{ task: nan }` → merged has `{ main: Value("role.md"), task: ExplicitNone }`

**File**: `zbobr-dispatcher/src/prompts.rs`
- Update any unit tests for `prompt_files_for_stage()` to use new IndexMap-based setup

**Why**: Tests must cover the new three-level map merge behavior and nan-clearing semantics that replace the old array+role_prompt fallback logic.
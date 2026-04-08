# Plan: prompts-should-be-hash

## Approach
Replace the dual `role_prompt`/`prompts` (Vec) scheme across RoleDefinition, StageDefinition, and add new workflow-level prompts, all using `IndexMap<String, TomlOption<PathBuf>>`. This enables named prompt slots with three-level inheritance (workflow → role → stage) and per-slot nan-clearing.

## Key design decisions
- **Chosen analog**: `TomlOption<T>` for per-value three-state semantics, `IndexMap` for ordered named slots — both already used in codebase
- **Map merge**: Per-key merge using `TomlOption::merge()` semantics — ExplicitNone (nan) clears a slot, Absent inherits from base, Value overrides
- **Breaking change**: Old `prompt` and `role_prompt` fields removed; existing configs must be updated
- **Order**: IndexMap preserves insertion order, so slot order defined at workflow level carries through to final prompt list

## Checklist items
1. Update RoleDefinition, StageDefinition, WorkflowConfig/Toml structs (+ MergeToml)
2. Update resolve_paths() for all three structs
3. Rewrite prompt_files_for_stage() with three-level merge helper
4. Update default config in init.rs
5. Update existing tests, add new tests for three-level merge and nan-clearing
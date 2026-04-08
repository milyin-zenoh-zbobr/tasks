# Updated Plan: prompts-should-be-hash

## Key change from original plan
Original plan used empty string `""` to clear a slot. The updated task description uses `nan` (deserialized via `TomlOption::ExplicitNone`) instead. This aligns with the existing `TomlOption` infrastructure already used in the codebase.

## Target config shape
```toml
[workflow]
prompts = { main = nan, task = "task.md" }

[workflow.roles.merger]
prompts = { main = "merger.md" }

[workflow.pipelines.merge.stages.merging]
prompts = { task = nan }
```

Result for `merger` role at `merging` stage: only `merger.md` (task cleared by stage, main set by role).

## Implementation areas

### 1. Config structs (`zbobr-api/src/config/mod.rs`)
- `RoleDefinition`: remove `prompt: TomlOption<PathBuf>`, add `prompts: Option<IndexMap<String, TomlOption<PathBuf>>>`
- `StageDefinition`: remove `role_prompt: TomlOption<PathBuf>` + `prompts: Option<Vec<PathBuf>>`, add `prompts: Option<IndexMap<String, TomlOption<PathBuf>>>`
- `WorkflowConfig` + `WorkflowToml`: add `prompts: Option<IndexMap<String, TomlOption<PathBuf>>>`

The `nan` → `ExplicitNone` deserialization already works via existing `TomlOption` custom Deserialize impl.

### 2. Per-key map merging (MergeToml)
Write a helper `merge_prompt_maps()` function: when overlay is Some, merge per-key using TomlOption semantics (Value overrides, ExplicitNone clears, absent inherits). Update MergeToml impls for all three structs to use it instead of `.or()`.

### 3. resolve_paths
Each struct's `resolve_paths()` iterates map values and resolves only `Value(path)` entries against the config dir.

### 4. Prompt resolution (`zbobr-dispatcher/src/prompts.rs`)
Rewrite `prompt_files_for_stage()`: three-level merge (workflow → role → stage), filter ExplicitNone, collect Value paths in order, prefix relative paths with prompts_dir.

### 5. Default config (`zbobr/src/init.rs`)
- Workflow: `prompts = { main = nan, task = "task.md" }`
- Roles: `prompts = { main = "planner.md" }` etc.
- Stages: remove per-stage prompts (inherited from workflow/role)

### 6. Tests
Update path resolution, merging, and prompt collection tests for new structure.

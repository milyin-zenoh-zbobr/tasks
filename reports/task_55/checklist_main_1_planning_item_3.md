## Default config changes

**File**: `zbobr/src/init.rs`

### default_workflow()
- **WorkflowConfig**: Add `prompts` field with `IndexMap` containing `{ "task" => TomlOption::Value(PathBuf::from("task.md")) }` (and optionally `"main" => ExplicitNone` as a placeholder slot)
- **RoleDefinition for each role**: Change from `prompt: TomlOption::Value(PathBuf::from("planner.md"))` to `prompts: Some(IndexMap::from([("main", TomlOption::Value(PathBuf::from("planner.md")))]))` — do the same for all roles (worker, reviewer, test_planner, test_worker, linter, linter_worker, tester, merger)
- **StageDefinition for each stage**: Remove `prompts: Some(vec![PathBuf::from("task.md")])` from all stages — the task prompt is now inherited from workflow-level `prompts` map

### TOML init template (if any)
If there is a TOML template string generated in init.rs or elsewhere, update it to reflect the new `prompts = { main = "role.md" }` format for roles and `prompts = { task = "task.md" }` for workflow.

**Why**: The default config demonstrates the intended usage: workflow defines shared task prompt in a "task" slot, each role defines its main prompt in a "main" slot, stages inherit both through the three-level merge. Removes redundancy of per-stage `prompts: [task.md]` repeated on every stage.
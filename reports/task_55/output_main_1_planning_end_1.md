Here's the updated plan summary:

**Key change from original:** Use `nan` (via `TomlOption::ExplicitNone`) to clear prompt slots, not empty string `""`. This leverages the existing `TomlOption` infrastructure already in the codebase.

**Prompt field type at all three levels:** `Option<IndexMap<String, TomlOption<PathBuf>>>`
- `Value(path)` — use this prompt file
- `nan` → `ExplicitNone` — suppress/clear this slot
- Key absent from map → inherit from parent level

**Areas to change:**
1. **Config structs** — Remove old `prompt`/`role_prompt`/`Vec<PathBuf>` fields; add unified `prompts: Option<IndexMap<String, TomlOption<PathBuf>>>` to WorkflowConfig, RoleDefinition, and StageDefinition
2. **MergeToml** — Write `merge_prompt_maps()` helper for per-key TomlOption semantics; update merge impls for all three structs
3. **resolve_paths** — Iterate map values and resolve only `Value(path)` entries
4. **`prompt_files_for_stage()`** — Three-level merge (workflow → role → stage), filter ExplicitNone, collect in order
5. **`default_workflow()`** — Workflow gets `{ main = nan, task = "task.md" }`, roles get `{ main = "role.md" }`, stages drop per-stage prompts
6. **Tests** — Update for new structure
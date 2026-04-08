Plan finalized and submitted for implementation. The 5 checklist items cover:

1. **Config structs** — swap `prompt`/`role_prompt`/`Vec<PathBuf>` fields for `IndexMap<String, TomlOption<PathBuf>>` on all three levels
2. **resolve_paths** — iterate map values instead of scalar/vec fields
3. **prompt_files_for_stage()** — rewrite with a `merge_prompt_maps()` helper doing workflow → role → stage three-level merge, filtering ExplicitNone entries
4. **Default config (init.rs)** — workflow gets `{ task: "task.md" }`, each role gets `{ main: "role.md" }`, per-stage prompts arrays removed
5. **Tests** — update existing tests, add new ones covering three-level merge and nan-clearing
## Prompt resolution changes

**File**: `zbobr-dispatcher/src/prompts.rs`

### prompt_files_for_stage()
Rewrite the function to:
1. Collect the workflow-level prompts map (from `workflow.prompts`)
2. Merge in the role-level prompts map (from `workflow.role_definition(role).prompts`) per-key using TomlOption semantics
3. Merge in the stage-level prompts map (from `stage_def.prompts`) per-key using TomlOption semantics
4. After three-level merge, filter out entries where value is `ExplicitNone`
5. Collect only `Value(path)` entries in insertion order (IndexMap preserves order)
6. Prefix relative paths with `workflow.prompts_dir` (same as current behavior)

A helper function `merge_prompt_maps()` can simplify steps 1-3:
- Takes two `Option<IndexMap<String, TomlOption<PathBuf>>>` values
- Returns merged `IndexMap<String, TomlOption<PathBuf>>` using per-key TomlOption merge
- Start with base map (cloned), overlay map's entries override per key using `TomlOption::merge()`

**Remove**: The old `role_prompt` fallback logic and `Vec<PathBuf>` extension

**Why**: The three-level merge (workflow → role → stage) with named slots replaces the old two-field `role_prompt`/`prompts` scheme. Slot ordering is defined by insertion order of the IndexMap.
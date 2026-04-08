## Config struct changes

**File**: `zbobr-api/src/config/mod.rs`

### RoleDefinition
- Remove `prompt: TomlOption<PathBuf>` field
- Add `prompts: Option<IndexMap<String, TomlOption<PathBuf>>>` field (with serde attributes `default, skip_serializing_if = "Option::is_none"`)

### StageDefinition
- Remove `role_prompt: TomlOption<PathBuf>` field
- Remove `prompts: Option<Vec<PathBuf>>` field
- Add `prompts: Option<IndexMap<String, TomlOption<PathBuf>>>` field (with serde attributes `default, skip_serializing_if = "Option::is_none"`)

### WorkflowConfig and WorkflowToml
- Add `prompts: Option<IndexMap<String, TomlOption<PathBuf>>>` field to WorkflowConfig (with serde attributes `default, skip_serializing_if = "Option::is_none"`)
- Add `prompts: Option<IndexMap<String, TomlOption<PathBuf>>>` field to WorkflowToml (with serde attributes `default, skip_serializing_if = "Option::is_none"`)

### MergeToml for prompts maps
The macro-generated merge logic for `Option<IndexMap<K, V>>` performs key-by-key merge using `MergeToml::merge_toml()`. Since `TomlOption<T>` implements `MergeToml`, and the merge semantics are: overlay's key wins unless absent, this will handle ExplicitNone (nan) clearing correctly.

However, for RoleDefinition and StageDefinition which use a hand-written or macro-generated MergeToml, check whether the macro handles their prompts field correctly or if a helper `merge_prompt_maps()` needs to be written. Follow the same per-key merge pattern as WorkflowToml's roles/pipelines merging (lines 479-507 in current mod.rs).

**Why**: Removes the dual `role_prompt`/`prompts` scheme, replacing it with a single named-slot map that supports per-key inheritance and nan-clearing across workflow → role → stage levels.
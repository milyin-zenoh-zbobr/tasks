## resolve_paths changes

**File**: `zbobr-api/src/config/mod.rs`

### RoleDefinition::resolve_paths()
- Remove handling of `self.prompt` (single PathBuf)
- Add iteration over `self.prompts` map values: for each `(_, TomlOption::Value(path))`, resolve relative paths against `config_dir`
- `ExplicitNone` and `Absent` entries do not need path resolution

### StageDefinition::resolve_paths()
- Remove handling of `self.role_prompt` and `self.prompts` (Vec<PathBuf>)
- Add iteration over `self.prompts` map values: for each `(_, TomlOption::Value(path))`, resolve relative paths against `config_dir`

### WorkflowConfig / WorkflowToml::resolve_paths()
- Add iteration over the new `prompts` map values for path resolution

**Pattern to follow**: The existing `resolve_paths()` for RoleDefinition (around line 44) shows the pattern — mutate the struct's field in place by mapping over values. Apply the same pattern to the IndexMap values.

**Why**: Ensures that relative prompt paths specified in config are made absolute relative to the config file's directory, consistent with existing path resolution behavior.
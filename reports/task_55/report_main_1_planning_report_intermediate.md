## Plan: Change prompts from arrays to IndexMap (hash)

### Problem
Currently prompts are configured as a single `prompt: PathBuf` on roles and `prompts: Vec<PathBuf>` array on stages, with a separate `role_prompt` override field. This is inflexible — there's no way to define named prompt "slots" that can be selectively overridden or cleared at different config levels.

### Proposed approach

Change all three config levels to use `prompts: IndexMap<String, PathBuf>` with three-level merge (workflow → role → stage). Empty string values clear a slot.

**Example config result:**
```toml
[workflow]
prompts = { main = "", task = "task.md" }

[workflow.roles.merger]
prompts = { main = "merger.md" }

[workflow.pipelines.merge]
stages.merging = { ... prompts = { task = "" } }
```

### Changes by area

1. **Config structs** (`zbobr-api/src/config/mod.rs`):
   - Add `prompts: IndexMap<String, PathBuf>` to WorkflowConfig/WorkflowToml
   - Replace `RoleDefinition.prompt` with `prompts: Option<IndexMap<String, PathBuf>>`
   - Replace `StageDefinition.role_prompt` + `prompts: Vec` with single `prompts: Option<IndexMap<String, PathBuf>>`
   - Update MergeToml impls for per-key IndexMap merging
   - Update resolve_paths to iterate IndexMap values

2. **Prompt resolution** (`zbobr-dispatcher/src/prompts.rs`):
   - Add `merge_prompts()` utility for three-level merge with empty-value filtering
   - Rewrite `prompt_files_for_stage()` to use merge_prompts instead of current role_prompt/array logic

3. **Default config** (`zbobr/src/init.rs`):
   - Workflow gets base `prompts = { main = "", task = "task.md" }`
   - Roles change from `prompt: "role.md"` to `prompts: { main = "role.md" }`
   - Stages no longer need per-stage `prompts: ["task.md"]` (inherited from workflow)

4. **Minor**: Update debug logging in `zbobr-dispatcher/src/cli.rs`, update all tests

### Key design decisions
- IndexMap preserves insertion order: workflow defines canonical slot order
- Empty PathBuf value = "remove this slot" (filtered out in final prompt list)
- Breaking change: old `prompt`/`role_prompt` fields no longer accepted
- No new dependencies needed (indexmap with serde already in use)
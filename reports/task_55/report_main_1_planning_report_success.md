# Comprehensive Prompt Structure Analysis for zbobr

## SUMMARY
The zbobr project currently uses ARRAY-based prompts (Vec<PathBuf>) for both roles and stages. The task requires converting these to IndexHash (hash maps) for better organization. This analysis covers all relevant config definitions, usage patterns, and initialization code.

---

## 1. CURRENT PROMPT STRUCTURE IN CONFIG

### 1.1 Role Prompts
**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs` (Lines 24-50)

```rust
#[derive(Clone, Debug, serde::Deserialize, serde::Serialize, Default)]
#[serde(deny_unknown_fields)]
pub struct RoleDefinition {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mcp: Option<Vec<McpTool>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt: Option<PathBuf>,  // <-- SINGLE prompt file
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool: Option<Tool>,
}
```

- **Current:** Single `prompt` field (Option<PathBuf>)
- **Location:** Lines 34-35
- **Merge behavior:** Lines 53-61 (uses simple `other.prompt.or(self.prompt)`)

### 1.2 Stage Prompts
**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs` (Lines 190-283)

```rust
pub struct StageDefinition {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub role: Option<Role>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub call: Option<Pipeline>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool: Option<Tool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub role_prompt: Option<PathBuf>,  // <-- Main role prompt override
    /// `None` means absent in config (inherit from base during merging, or no extra prompts at runtime).
    /// `Some(vec![])` explicitly sets an empty list.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompts: Option<Vec<PathBuf>>,  // <-- ARRAY of extra prompts
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub on_success: Option<StageTransition>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub on_failure: Option<StageTransition>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub on_intermediate: Option<StageTransition>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub on_no_report: Option<StageTransition>,
}
```

- **Current:** Two fields:
  - `role_prompt`: Option<PathBuf> (single prompt file, overrides role's prompt)
  - `prompts`: Option<Vec<PathBuf>> (array of extra prompt files)
- **Location:** Lines 200-222
- **Merge behavior:** Lines 269-282 (uses `other.{field}.or(self.{field})`)
- **Path resolution:** Lines 226-238 (handles both fields, maps relative to absolute paths)

### 1.3 Workflow-Level Prompts
**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs` (Lines 403-429)

```rust
pub struct WorkflowConfig {
    /// Base directory for prompt files; prepended to relative prompt paths.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompts_dir: Option<PathBuf>,  // <-- Shared base directory only
    #[serde(default)]
    pub roles: IndexMap<Role, RoleDefinition>,
    #[serde(default)]
    pub pipelines: HashMap<Pipeline, PipelineConfig>,
}

pub struct WorkflowToml {
    #[serde(default)]
    pub prompts_dir: Option<PathBuf>,
    #[serde(default)]
    pub roles: Option<IndexMap<Role, RoleDefinition>>,
    #[serde(default)]
    pub pipelines: Option<HashMap<Pipeline, PipelineConfig>>,
}
```

- **Current:** Only has `prompts_dir` (a shared base directory)
- **Missing:** No workflow-level `prompts` field (this is what needs to be added)
- **Location:** Lines 409-429

### 1.4 Pipeline Stage Container
**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs` (Lines 285-342)

```rust
pub struct PipelineConfig {
    #[serde(default)]
    pub stages: IndexMap<Stage, StageDefinition>,
}
```

- Stages are stored in `IndexMap<Stage, StageDefinition>` (preserves insertion order)
- Location: Lines 285-342

---

## 2. USAGE PATTERNS: HOW PROMPTS ARE CONSUMED

### 2.1 Prompt File Collection Function
**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-dispatcher/src/prompts.rs` (Lines 192-224)

```rust
pub fn prompt_files_for_stage(
    stage_def: &StageDefinition,
    workflow: &WorkflowConfig,
) -> Vec<PathBuf> {
    let mut files = Vec::new();
    // 1. Add stage's role_prompt override (if set)
    if let Some(ref main) = stage_def.role_prompt {
        files.push(main.clone());
    } else if let Some(role_def) = stage_def
        .role()
        .map(|r| r.as_str())
        .and_then(|r| workflow.role_definition(r))
        && let Some(ref prompt_path) = role_def.prompt  // <-- Falls back to role's prompt
    {
        files.push(prompt_path.clone());
    }
    // 2. Add stage's extra prompts array
    files.extend(stage_def.prompts.iter().flatten().cloned());
    // 3. Prefix relative paths with workflow.prompts_dir
    if let Some(ref prompts_dir) = workflow.prompts_dir {
        files = files
            .into_iter()
            .map(|p| {
                if p.is_relative() {
                    prompts_dir.join(&p)
                } else {
                    p
                }
            })
            .collect();
    }
    files
}
```

**Key observations:**
- Returns Vec<PathBuf> (ordered list of files to load)
- Fallback chain: stage role_prompt → role's prompt → stage's prompts array
- Relative paths are prefixed with `workflow.prompts_dir`

### 2.2 Prompt Loading
**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-dispatcher/src/prompts.rs` (Lines 226-262)

```rust
pub fn load_prompts(paths: &[PathBuf], base_path: Option<&PathBuf>) -> anyhow::Result<String> {
    let mut combined = String::new();
    for path in paths.iter() {
        // ... path resolution logic ...
        let content = std::fs::read_to_string(&resolved_path)?;
        let trimmed = content.trim();
        if trimmed.is_empty() {
            continue;
        }
        if !combined.is_empty() {
            combined.push_str("\n\n");
        }
        combined.push_str(trimmed);
    }
    Ok(combined)
}
```

**Key observations:**
- Multiple prompt files are concatenated with "\n\n" between them
- Empty files are skipped
- Paths are resolved relative to `base_path` if provided

### 2.3 Prompt Building Usage
**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-dispatcher/src/prompts.rs` (Lines 52-120)

- `build_for_stage()`: Lines 53-70 - calls `prompt_files_for_stage()` then `load_prompts()`
- `validate_all_prompts()`: Lines 72-98 - iterates all stages and validates prompts
- `build_for_stage_with_task()`: Lines 100-120 - same flow but with provided task data

All usage paths go through the `prompt_files_for_stage()` → `load_prompts()` chain.

---

## 3. INITIALIZATION AND DEFAULT CONFIG

### 3.1 Default Workflow Creation
**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr/src/init.rs` (Lines 365-483)

```rust
fn default_workflow() -> WorkflowConfig {
    // ...
    let task_prompt = vec![PathBuf::from(TASK_PROMPT)];  // <-- "task.md"
    
    let main_stages = IndexMap::from([
        (
            STAGE_PLANNING,
            StageDefinition {
                role: Some(ROLE_PLANNER),
                prompts: Some(task_prompt.clone()),  // <-- Array with one element
                on_intermediate: Some(StageTransition::pause()),
                ..Default::default()
            },
        ),
        // ... more stages ...
    ]);
    
    let roles = IndexMap::from([
        (
            ROLE_PLANNER,
            RoleDefinition {
                mcp: Some(vec![...]),
                prompt: Some(PathBuf::from("planner.md")),  // <-- Single prompt file
                tool: Some(TOOL_PLANNER),
            },
        ),
        // ... more roles ...
    ]);
    
    let mut pipelines = HashMap::new();
    pipelines.insert(
        Pipeline::Main,
        PipelineConfig { stages: main_stages },
    );
    
    WorkflowConfig {
        prompts_dir: Some(PathBuf::from(WORKFLOW_PROMPTS_DIR)),  // "prompts"
        roles,
        pipelines,
    }
}
```

**Key observations:**
- All stages use `prompts: Some(vec![PathBuf::from("task.md")])` (array with one element)
- All roles use `prompt: Some(PathBuf::from("{role_name}.md"))` (single file)
- All this happens in init.rs around lines 365-483
- Default `prompts_dir` is set to "prompts" (line 618)

### 3.2 Prompt Files Directory
**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr/src/init.rs` (Lines 35-37, 119-130)

```rust
const WORKFLOW_PROMPTS_DIR: &str = "prompts";
const TASK_PROMPT: &str = "task.md";

// In init_workspace():
let prompts_dir = dest.join("prompts");
tokio::fs::create_dir_all(&prompts_dir).await?;

for (name, content) in PROMPT_FILES {
    let path = prompts_dir.join(format!("{name}.md"));
    write_or_new(&path, content, force).await?;
}
```

Prompt files created: planner.md, worker.md, reviewer.md, test_planner.md, test_worker.md, linter.md, linter_worker.md, tester.md, merger.md

---

## 4. ROLE AND STAGE KEY TYPES

### 4.1 Role Type
**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/role.rs` (Lines 1-73)

```rust
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Role(pub std::borrow::Cow<'static, str>);
```

- Implements: Debug, Clone, PartialEq, Eq, Hash, Display, Deref, Borrow<str>
- Implements serde (De/Serialize), JsonSchema
- Can be used as a map key (it's Hashable and Eq)
- Used in: `IndexMap<Role, RoleDefinition>` in WorkflowConfig

### 4.2 Stage Type
**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/stage.rs` (Lines 1-67)

```rust
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Stage(pub std::borrow::Cow<'static, str>);
```

- Implements: Debug, Clone, PartialEq, Eq, Hash, Display, Deref, Borrow<str>
- Implements serde (De/Serialize), JsonSchema
- Can be used as a map key (it's Hashable and Eq)
- Used in: `IndexMap<Stage, StageDefinition>` in PipelineConfig

---

## 5. INDEXMAP USAGE

### 5.1 Current IndexMap Uses
**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs` (Line 3-4, 292, 414, 426, 723)

```rust
use indexmap::IndexMap;

// In PipelineConfig:
pub struct PipelineConfig {
    #[serde(default)]
    pub stages: IndexMap<Stage, StageDefinition>,  // Line 292
}

// In WorkflowConfig:
pub struct WorkflowConfig {
    pub roles: IndexMap<Role, RoleDefinition>,     // Line 414
    pub pipelines: HashMap<Pipeline, PipelineConfig>,
}

// In WorkflowToml:
pub struct WorkflowToml {
    pub roles: Option<IndexMap<Role, RoleDefinition>>,  // Line 426
    pub pipelines: Option<HashMap<Pipeline, PipelineConfig>>,
}
```

- ImportMap v2 is used (with serde feature enabled)
- Workspace dependency at line 41 in Cargo.toml: `indexmap = { version = "2", features = ["serde"] }`
- Currently used for:
  - `IndexMap<Stage, StageDefinition>` (stages within a pipeline)
  - `IndexMap<Role, RoleDefinition>` (roles in workflow)
  - `IndexMap<Provider, ResolvedProvider>` (providers)
  - `IndexMap<Tool, Vec<ToolEntry>>` (tools)

### 5.2 IndexHash - NOT Currently Used
No type alias `IndexHash` exists in the codebase yet. This will need to be created as:
```rust
pub type IndexHash<K, V> = IndexMap<K, V>;
```

---

## 6. SERIALIZATION/DESERIALIZATION

### 6.1 Config Merging
**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs`

- `RoleDefinition`: Implements `MergeToml` (Lines 53-61)
  - Uses: `other.field.or(self.field)` for all fields
- `StageDefinition`: Implements `MergeToml` (Lines 269-282)
  - Uses: `other.field.or(self.field)` for all fields
- `WorkflowToml`: Implements `merge_toml()` (Lines 476-508)
  - Has custom logic for merging maps (Roles and Pipelines)

### 6.2 Path Resolution
- `RoleDefinition::resolve_paths()`: Lines 44-50
- `StageDefinition::resolve_paths()`: Lines 226-238
- `WorkflowToml::resolve_paths()`: Lines 519-541

All path resolution happens against a config base directory or prompts_dir.

### 6.3 Serde Attributes
- All config structs use `#[serde(deny_unknown_fields)]`
- Optional fields use `#[serde(default, skip_serializing_if = "Option::is_none")]`
- This applies to: RoleDefinition (Lines 28-39), StageDefinition (Lines 198-222), WorkflowConfig (Lines 407-417), WorkflowToml (Lines 420-429)

---

## 7. WORKFLOW CONFIG ACCESSOR METHODS

**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs` (Lines 568-639)

```rust
impl WorkflowConfig {
    pub fn pipeline(&self, name: &Pipeline) -> Option<&PipelineConfig>
    pub fn stage(&self, pipeline: &Pipeline, stage: &Stage) -> Option<&StageDefinition>
    pub fn start_stage_for_pipeline(&self, pipeline: &Pipeline) -> Option<(&Stage, &StageDefinition)>
    pub fn default_pipeline(&self) -> Pipeline
    pub fn pipeline_names(&self) -> Vec<&Pipeline>
    pub fn find_stage_by_role(&self, role: &str) -> Option<(&Pipeline, &str, &StageDefinition)>
    pub fn role_definition(&self, role: &str) -> Option<&RoleDefinition>  // Line 626
    pub fn all_stages(&self) -> Vec<(&Pipeline, &str, &StageDefinition)>
    pub fn validate(&self) -> anyhow::Result<()>
}
```

Key method: `role_definition()` at line 626 uses `self.roles.get(role)` which works with Role struct key via Borrow trait.

---

## 8. TESTS AND EXAMPLES

### 8.1 Config Tests
**File:** `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs` (Lines 1605-2104)

Key test cases related to prompts:
- `role_definition_resolve_paths_makes_prompt_absolute()`: Lines 1605-1617
- `role_definition_resolve_paths_preserves_absolute()`: Lines 1619-1626
- `stage_definition_resolve_paths_resolves_all_prompt_fields()`: Lines 1630-1648
  - Tests resolution of `role_prompt` and `prompts` (array) fields
- `pipeline_config_resolve_paths_resolves_stage_prompts()`: Lines 1651-1672
- `workflow_toml_resolve_paths_resolves_nested_prompt_fields()`: Lines 1676-1725
- `workflow_toml_merge_preserves_resolved_paths()`: Lines 1729-1765
- `workflow_toml_merge_roles_key_wise()`: Lines 1771-1825
  - Tests merging of role definitions in IndexMap

---

## 9. KEY FACTS FOR REFACTORING

1. **No IndexHash yet exists** - will need to create it as a type alias
2. **Current role prompts are single files** - can be wrapped as `IndexHash<String, PathBuf>` if we want named prompts
3. **Current stage prompts are arrays** - currently `Vec<PathBuf>`, needs to become `IndexHash<String, PathBuf>`
4. **Workflow level has no prompts** - only `prompts_dir`; needs new `prompts: Option<IndexHash<String, PathBuf>>` field
5. **Merging logic will change** - simple `or()` won't work for maps; need key-wise merge like roles/pipelines (see lines 479-507)
6. **Path resolution must handle map values** - currently handles Option<PathBuf> and Option<Vec<PathBuf>>
7. **Serialization must preserve order** - IndexMap is already used for this in stages/roles
8. **All accessor methods use `.get()` with string keys** - role_definition() uses `.get(role)` where role is &str
9. **Fallback logic for stage prompts** - currently in `prompt_files_for_stage()` at lines 195-224, may need adaptation if structure changes
10. **Tests will need updates** - especially merge and path resolution tests (lines 1730-2104)

---

## FILES THAT WILL NEED CHANGES

1. `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs` - Main config definitions
2. `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-dispatcher/src/prompts.rs` - Prompt loading logic
3. `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr/src/init.rs` - Default config initialization
4. Tests in config/mod.rs - Path resolution, merging, validation tests
5. Possibly `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-utility/src/lib.rs` - If new type alias goes there

---

## SUMMARY OF CURRENT STRUCTURE

```
WorkflowConfig {
    prompts_dir: Option<PathBuf>,                           // Shared base directory
    roles: IndexMap<Role, RoleDefinition>,
    pipelines: HashMap<Pipeline, PipelineConfig>,
}

RoleDefinition {
    prompt: Option<PathBuf>,                                // Single prompt file
    mcp: Option<Vec<McpTool>>,
    tool: Option<Tool>,
}

PipelineConfig {
    stages: IndexMap<Stage, StageDefinition>,
}

StageDefinition {
    role_prompt: Option<PathBuf>,                           // Override single prompt
    prompts: Option<Vec<PathBuf>>,                          // Array of extra prompts
    role: Option<Role>,
    call: Option<Pipeline>,
    tool: Option<Tool>,
    on_success: Option<StageTransition>,
    on_failure: Option<StageTransition>,
    on_intermediate: Option<StageTransition>,
    on_no_report: Option<StageTransition>,
}
```

**To be changed to:**

```
WorkflowConfig {
    prompts_dir: Option<PathBuf>,
    prompts: Option<IndexHash<String, PathBuf>>,           // NEW: Workflow-level prompts
    roles: IndexMap<Role, RoleDefinition>,
    pipelines: HashMap<Pipeline, PipelineConfig>,
}

RoleDefinition {
    prompts: Option<IndexHash<String, PathBuf>>,           // CHANGED: Array → Map
    mcp: Option<Vec<McpTool>>,
    tool: Option<Tool>,
}

StageDefinition {
    prompts: Option<IndexHash<String, PathBuf>>,           // CHANGED: Array → Map
    role: Option<Role>,
    call: Option<Pipeline>,
    tool: Option<Tool>,
    on_success: Option<StageTransition>,
    on_failure: Option<StageTransition>,
    on_intermediate: Option<StageTransition>,
    on_no_report: Option<StageTransition>,
}
```

(Note: role_prompt would be removed as it would be consolidated into the prompts map)
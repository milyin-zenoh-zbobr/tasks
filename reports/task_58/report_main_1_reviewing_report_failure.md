## Overall assessment
The analog choice was reasonable: introducing a dedicated `TomlOption<T>` and threading it through merge code matches the existing custom-serde / `MergeToml` patterns well. The merge-layer changes are mostly consistent with that plan.

However, the implementation is **not complete end-to-end**. Several downstream consumers still convert `TomlOption` to plain `Option` too early, which collapses **`ExplicitNone`** and **`Absent`** back together. That breaks the core requirement of this task: `nan` should explicitly clear inherited values.

## Findings

### 1. Provider inheritance still treats `ExplicitNone` as "inherit from parent"
**Files:** `zbobr-api/src/config/mod.rs:927-945`

`resolve_single_provider()` uses `into_option()` / `or(...)` when flattening provider inheritance:

- `executor: def.executor.clone().into_option().unwrap_or(parent.executor)`
- `priority: def.priority.clone().into_option().unwrap_or(parent.priority)`
- `plan_mode: def.plan_mode.clone().into_option().unwrap_or(parent.plan_mode)`
- `access_key: def.access_key.clone().into_option().or(parent.access_key)`

That means a child provider configured with `executor = nan`, `priority = nan`, `plan_mode = nan`, or `access_key = nan` behaves exactly like an absent field and silently inherits the parent value.

That is a direct semantic regression from the new three-state design. The branch’s new tests only assert that the merged TOML contains `TomlOption::ExplicitNone`; they do **not** verify the final resolved provider behavior, so this slipped through.

**Why it matters:** the new feature is supposed to let overlay configs clear inherited values. For providers, clearing currently does not work once resolution runs.

### 2. `stage.tool = nan` does not clear the role-level tool fallback
**Files:** `zbobr-api/src/config/mod.rs:879-897`

`resolve_tool()` checks `stage_def.tool.as_option()` and, if that returns `None`, falls back to `role_def.tool.as_option()`.

Because `as_option()` returns `None` for both `Absent` and `ExplicitNone`, a stage with `tool = nan` cannot suppress the role’s tool. It still resolves to the role-level tool as if the stage override were omitted.

**Why it matters:** this is another end-to-end breakage of the new clearing semantics. The merge layer preserves `ExplicitNone`, but resolution loses it.

### 3. `role_prompt = nan` does not clear the role-level prompt fallback
**Files:** `zbobr-dispatcher/src/prompts.rs:201-208`

`prompt_files_for_stage()` does:

- use `stage_def.role_prompt.as_option()` if present
- otherwise fall back to `role_def.prompt.as_option()`

Again, `ExplicitNone` is collapsed to `None`, so `role_prompt = nan` behaves like an absent field and still pulls in the role prompt.

**Why it matters:** prompt inheritance is one of the main overlay use cases, and this path currently defeats explicit clearing.

## Pattern-consistency assessment
The planner chose a good analog and the merge/data-model work follows project patterns reasonably well. The inconsistency is in the final consumer layer: code that previously treated `Option<T>` as enough was mechanically switched to `TomlOption<T>`, but several fallback/resolution sites still use `as_option()` / `into_option()` in places where they must distinguish **Absent** from **ExplicitNone**.

## Suggested fix direction
Audit all fallback logic that interprets TOML-layer values after merge. Anywhere behavior differs between:

- "field missing, inherit/fallback"
- "field explicitly cleared, stop inheritance"

must match on `TomlOption` directly instead of immediately converting through `as_option()` / `into_option()`.

At minimum, fix and add behavior-oriented tests for:

1. provider resolution with a child clearing inherited `executor` / `access_key`
2. `resolve_tool()` with a stage clearing a role-level tool
3. `prompt_files_for_stage()` with a stage clearing a role-level prompt

I did not check any checklist items because the context already showed all checklist items as completed; the failure is due to correctness issues in the implemented behavior.
# TomlOption Type and TOML Deserialization Analysis

## 1. TomlOption Definition and Variants

**File**: `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-utility/src/toml_option.rs` (lines 18-26)

```rust
#[derive(Clone, Debug, PartialEq)]
pub enum TomlOption<T> {
    /// Field was not present in the TOML source.
    Absent,
    /// Field was explicitly set to `nan` — clears inherited value.
    ExplicitNone,
    /// Field carries a normal value.
    Value(T),
}
```

Three distinct variants:
- **Absent**: Field missing from TOML → inherit from base during merge
- **ExplicitNone**: Field set to `nan` in TOML → explicitly clear any base value
- **Value(T)**: Normal value present → overrides base

## 2. Custom Deserialize Implementation for `nan` Detection

**File**: `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-utility/src/toml_option.rs` (lines 115-194)

Key implementation details:

1. **Custom Visitor** (lines 136-194): `TomlOptionVisitor<T>` intercepts deserialization:
   - `visit_f64()` (lines 143-150): **Detects NaN floats and returns `ExplicitNone`**
     ```rust
     fn visit_f64<E: serde::de::Error>(self, v: f64) -> Result<Self::Value, E> {
         if v.is_nan() {
             Ok(TomlOption::ExplicitNone)
         } else {
             // Forward to T's deserializer
             T::deserialize(v.into_deserializer()).map(TomlOption::Value)
         }
     }
     ```
   - Other visit methods forward to `T::Deserialize`
   - `visit_none()` (lines 180-182): Returns `Absent` when field missing
   - `visit_seq()` and `visit_map()` (lines 166-178): Handle structured types

2. **Serialization** (lines 102-113): 
   - `Absent` → serialized as null (skipped with `#[serde(skip_serializing_if)]`)
   - `ExplicitNone` → serialized as `f64::NAN`
   - `Value(v)` → serialized normally

3. **Serde Requirements**: Fields must use:
   ```rust
   #[serde(default, skip_serializing_if = "TomlOption::is_absent")]
   pub field: TomlOption<T>,
   ```

## 3. Usage in Config Structs (RoleDefinition and StageDefinition)

**File**: `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs`

### RoleDefinition (lines 32-41)

```rust
pub struct RoleDefinition {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mcp: Option<Vec<McpTool>>,
    #[serde(default, skip_serializing_if = "TomlOption::is_absent")]
    pub prompt: TomlOption<PathBuf>,  // ← Uses TomlOption for scalar field
    #[serde(default, skip_serializing_if = "TomlOption::is_absent")]
    pub tool: TomlOption<Tool>,       // ← Uses TomlOption for scalar field
}
```

**Current behavior**: 
- `prompt` and `tool` use `TomlOption` (three-state)
- `mcp` uses `Option` (two-state, list field)

### StageDefinition (lines 201-223)

```rust
pub struct StageDefinition {
    #[serde(default, skip_serializing_if = "TomlOption::is_absent")]
    pub role: TomlOption<Role>,
    #[serde(default, skip_serializing_if = "TomlOption::is_absent")]
    pub call: TomlOption<Pipeline>,
    #[serde(default, skip_serializing_if = "TomlOption::is_absent")]
    pub tool: TomlOption<Tool>,
    #[serde(default, skip_serializing_if = "TomlOption::is_absent")]
    pub role_prompt: TomlOption<PathBuf>,
    // This is currently a simple list, NOT a map:
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompts: Option<Vec<PathBuf>>,      // ← Scalar list (not map)
    #[serde(default, skip_serializing_if = "TomlOption::is_absent")]
    pub on_success: TomlOption<StageTransition>,
    // ... more fields
}
```

**Key insight**: `prompts` field currently uses `Option<Vec<PathBuf>>` (two-state), NOT a map.

## 4. Can `IndexMap<String, TomlOption<PathBuf>>` be used as a map value?

**YES, with specific semantics from the macro.**

The macro in `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-macros/src/lib.rs` (line 348-394) has **special handling for map fields**:

```rust
// Line 348-349: Map fields keep Option<T> (key-by-key merge); 
// other leaf fields use TomlOption<T>.
let use_toml_option = !is_map_type(&value_ty);
```

**Map type detection** (lines 983-990):
```rust
fn is_map_type(ty: &Type) -> bool {
    if let Type::Path(type_path) = ty {
        if let Some(last) = type_path.path.segments.last() {
            return last.ident == "IndexMap" || last.ident == "HashMap";
        }
    }
    false
}
```

**Map field merge logic** (lines 379-394):
When field is `Option<IndexMap<K, V>>`:
```rust
merge_toml_fields.push(quote! {
    #field_ident: match (self.#field_ident, other.#field_ident) {
        (Some(mut base), Some(over)) => {
            for (k, over_v) in over {
                if let Some(base_v) = base.get(&k).cloned() {
                    // KEY-BY-KEY MERGE with MergeToml trait
                    base.insert(k, ::zbobr_utility::MergeToml::merge_toml(base_v, over_v));
                } else {
                    base.insert(k, over_v);
                }
            }
            Some(base)
        }
        (None, over) => over,
        (base, None) => base,
    },
});
```

**Critical limitation**: Map fields use `Option<T>` in the generated Toml struct, NOT `Option<TomlOption<T>>`. This means:
- The map itself can be `Absent` (None) or `Value(Some(map))`
- Individual map values are NOT three-state; they follow `MergeToml::merge_toml()` semantics
- For `PathBuf` values, this means `merge_toml(self, other) → other` (wholesale replacement)

## 5. How `TomlOption::merge()` Works

**File**: `/data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-utility/src/toml_option.rs` (lines 75-86)

```rust
/// Merge two `TomlOption` values: overlay wins unless it is `Absent`.
/// Truth table (self=base, other=overlay → result):
/// - `(_, Value(v))` → `Value(v)`
/// - `(_, ExplicitNone)` → `ExplicitNone`
/// - `(base, Absent)` → `base`
pub fn merge(self, other: Self) -> Self {
    match other {
        Self::Absent => self,
        _ => other,
    }
}
```

**Merge truth table** (verified by tests at lines 280-341):
| Base | Overlay | Result |
|------|---------|--------|
| Value(a) | Value(b) | Value(b) |
| Value(a) | ExplicitNone | ExplicitNone |
| Value(a) | Absent | Value(a) |
| ExplicitNone | Value(b) | Value(b) |
| ExplicitNone | ExplicitNone | ExplicitNone |
| ExplicitNone | Absent | ExplicitNone |
| Absent | Value(b) | Value(b) |
| Absent | ExplicitNone | ExplicitNone |
| Absent | Absent | Absent |

Also implements `MergeToml` trait (lines 200-204):
```rust
impl<T> super::MergeToml for TomlOption<T> {
    fn merge_toml(self, other: Self) -> Self {
        self.merge(other)
    }
}
```

## 6. Recent zbobr_fix-58-nan-values-in-config Changes

**Commit**: `5bf3b37c` (commit message shows major refactoring)

Key changes in merge commit:
1. **Created `TomlOption<T>` type** in `zbobr-utility/src/toml_option.rs`
2. **Updated macro** to generate `TomlOption<T>` for all non-map leaf fields (not just simple fields)
3. **Updated all consumer code** to handle `ExplicitNone` semantics:
   - `resolve_tool()`: ExplicitNone blocks inheritance, returns error
   - `resolve_single_provider()`: Field-specific handling (error for executor, reset to defaults for priority/plan_mode, None for access_key)
   - `prompt_files_for_stage()`: ExplicitNone blocks role-level prompt inheritance

**Test examples** (lines 2625-2672):
- `stage_on_success_nan_in_overlay_clears_base_transition()`: Shows three-level scenario
- `workflow_prompts_dir_nan_in_overlay_clears_base()`: Shows nan clearing inherited value
- `workflow_prompts_dir_nan_resolves_to_none_in_config()`: Shows ExplicitNone → None conversion

## 7. Should `prompts` be `IndexMap<String, TomlOption<PathBuf>>`?

### Current implementation
- `prompts: Option<Vec<PathBuf>>` in config structs
- Two-state semantics: None = inherit, Some(vec) = replace wholesale
- Used in `prompt_files_for_stage()` at line 220: `files.extend(stage_def.prompts.iter().flatten().cloned());`

### Macro would generate for `Option<IndexMap<String, TomlOption<PathBuf>>>`

If the field were changed to `IndexMap<String, PathBuf>` in the config struct:

**Generated Toml struct field** (based on lines 368-373):
```rust
pub prompts: Option<IndexMap<String, PathBuf>>,  // NOT Option<TomlOption<...>>
```

**Map merge logic** (lines 379-394):
- Key-by-key merging: overlay keys override base keys
- Values use `PathBuf::merge_toml()` which is wholesale replacement (line 38-41)
- Map itself is Absent/Present (None/Some), not three-state

**Individual PathBuf values would NOT be three-state**:
- Cannot set individual prompt entries to `nan` to clear them
- Only wholesale map replacement or per-key override

### Key limitation for three-level merging

For a hypothetical `IndexMap<String, TomlOption<PathBuf>>` field:
- **The map as a whole** uses `Option<T>` semantics (two-state)
- **Individual values** inside the map would be three-state, but the macro doesn't generate this
- **The macro treats map value types as scalar** and applies `MergeToml` trait, not `TomlOption` wrapping

**Example**: Base has `{a: "/path/a", b: "/path/b"}`, overlay has `{a: nan}`:
- Current behavior: Overlay's `a` overwrites base's `a` to `nan` (invalid PathBuf)
- Three-state behavior would need: Overlay's `{a: ExplicitNone}` to signal "clear a from inherited map"
- **The macro doesn't support this automatically**

## 8. Three-Level Merging with `nan`

From test at lines 2625-2649:

```rust
#[test]
fn stage_on_success_nan_in_overlay_clears_base_transition() {
    let base_toml = r#"
[pipelines.main.stages.working]
on_success = "reviewing"
"#;
    let overlay_toml = r#"
[pipelines.main.stages.working]
on_success = nan
"#;
    let base: WorkflowToml = toml::from_str(base_toml).unwrap();
    let overlay: WorkflowToml = toml::from_str(overlay_toml).unwrap();

    let merged = base.merge_toml(overlay);
    let stage = merged
        .pipelines.as_ref().unwrap()[&Pipeline::Main]
        .stage(&Stage::from("working")).unwrap();

    // ExplicitNone should clear the inherited on_success transition
    assert_eq!(stage.on_success, TomlOption::ExplicitNone);
    assert!(stage.on_success().is_none(),
        "nan on_success must produce None at runtime");
}
```

**Three-level merging flow**:
1. Load base TOML → `on_success = StageTransition(...)`
2. Load overlay TOML → `on_success = nan` → deserializes as `ExplicitNone`
3. Merge: `StageTransition.merge(ExplicitNone)` → `ExplicitNone` (overlay wins)
4. Try into config: `ExplicitNone.into_option()` → `None` (at runtime)

This works for scalar fields with `TomlOption`. For maps, a custom implementation would be needed.

## Summary

- **TomlOption** enables three-state configuration with `nan`-as-null semantics
- **Scalar leaf fields** automatically use `TomlOption` via macro
- **Map fields** currently use `Option<T>` with key-by-key merging (two-state)
- **`IndexMap<String, TomlOption<PathBuf>>`** would require manual implementation OR macro enhancement
- **Current `prompts` field** is `Option<Vec<PathBuf>>`, not a map
- **Recent changes** (commit 5bf3b37c) introduced comprehensive nan-clearing support for scalar fields across all consumer code paths

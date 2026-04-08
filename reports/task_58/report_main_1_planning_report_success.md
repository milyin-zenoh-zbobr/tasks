# Config System Exploration Report

## Key Files Overview

**Macro Definition:**
- `/data/home/skynet/tasks/workspaces/zbobr/task-58/zbobr/zbobr-macros/src/lib.rs` (925 lines)
  - Proc-macro `config_struct` at lines 10-26
  - Full expansion logic in `expand_config_struct()` starting at line 28

**Utility Crate:**
- `/data/home/skynet/tasks/workspaces/zbobr/task-58/zbobr/zbobr-utility/src/lib.rs`
  - `MergeToml` trait definition at lines 19-21
  - `PrefixedArgs` trait at lines 43-51
  - Re-exports `config_struct` macro via `pub use zbobr_macros::config_struct` (line 7)
- `/data/home/skynet/tasks/workspaces/zbobr/task-58/zbobr/zbobr-utility/src/macros.rs` (single line)
  - Just re-exports: `pub use zbobr_macros::config_struct`
- `/data/home/skynet/tasks/workspaces/zbobr/task-58/zbobr/zbobr-utility/src/secret.rs`
  - Excellent example of custom serde deserialization with helper enum pattern (lines 84-113)

**Config Types:**
- `/data/home/skynet/tasks/workspaces/zbobr/task-58/zbobr/zbobr-api/src/config/mod.rs` (88,603 bytes)
  - `RoleDefinition` struct at line 31 with `MergeToml` impl at lines 54-62
  - `ProviderDefinition` struct at line 67 with `MergeToml` impl at lines 87-97
  - `StageDefinition` struct at line 200 with `MergeToml` impl at lines 269-283
  - `WorkflowToml` struct at line 422 with `merge_toml()` at lines 476-508
  - `StageTransition` custom serde at lines 159-189 (untagged enum pattern)
- `/data/home/skynet/tasks/workspaces/zbobr/task-58/zbobr/zbobr-api/src/config/tool.rs`
  - `Tool` newtype with custom serde (lines 53-63)
- `/data/home/skynet/tasks/workspaces/zbobr/task-58/zbobr/zbobr-api/src/config/role.rs`
  - `Role` newtype with custom serde (lines 52-62)
- `/data/home/skynet/tasks/workspaces/zbobr/task-58/zbobr/zbobr-api/src/config/stage.rs`
  - `Stage` newtype with custom serde (lines 46-56)

---

## MergeToml Trait Design

**Location:** `/data/home/skynet/tasks/workspaces/zbobr/task-58/zbobr/zbobr-utility/src/lib.rs` lines 10-28

```rust
pub trait MergeToml: Sized {
    fn merge_toml(self, other: Self) -> Self;
}

// For Vec<T> (lists always replaced wholesale)
impl<T> MergeToml for Vec<T> {
    fn merge_toml(self, other: Self) -> Self {
        other  // "other" (overlay) fully replaces "self" (base)
    }
}

// For PathBuf (scalars replaced wholesale)
impl MergeToml for std::path::PathBuf {
    fn merge_toml(self, other: Self) -> Self {
        other
    }
}
```

**Comment at lines 10-18 explains the semantics:**
- For `Option` scalar fields: overlay's value wins using `.or()` semantics
- For map fields: merged key-by-key with recursive merging for matching keys
- For list fields: replace base wholesale
- For `Option<Vec<_>>`: `None` = "inherit from base"; `Some(v)` (even `Some(vec![])`) = "replace base"

---

## Macro-Generated Toml Structs

The `#[config_struct]` macro generates THREE related structs from one annotated `*Config` struct:

### 1. `*Toml` struct
**Generated at lines 503-507 in macro:**
```rust
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default, deny_unknown_fields)]
pub struct NameToml {
    // All fields are Option<T>, even if Config has required fields
    // Scalars: Option<ScalarType>
    // Nested: Option<NestedToml>
    // Lists: Option<Vec<T>>
}
```

**Key properties:**
- All fields wrapped in `Option<_>` to distinguish absent from present
- Derives `Serialize`, `Deserialize` with `#[serde(default, deny_unknown_fields)]`
- Implements three methods (lines 524-548):
  - `merge_with_args(self, args: Args) -> Self` — applies CLI args
  - `merge_toml(self, other: Self) -> Self` — merges two Toml versions
  - `resolve_paths(self, config_dir: &Path) -> Self` — resolves relative paths

### 2. `*Args` struct
Generated at lines 517-520 in macro:
```rust
#[derive(Debug, Clone, Default)]
pub struct NameArgs {
    // Nested Args types (for CLI parsing)
}
```
- Implements `clap::Args` and `zbobr_utility::PrefixedArgs`
- Used to capture CLI overrides

### 3. `*ArgsDerived` struct
Generated at lines 511-514 in macro (internal only):
```rust
#[derive(Debug, Clone, clap::Args, Default)]
struct NameArgsDerived {
    // Only leaf (non-nested) fields for direct clap parsing
}
```
- Not public; used only by `*Args` for clap integration

---

## Merge Logic: How `.or()` Works for Option Fields

**Location:** zbobr-macros/src/lib.rs lines 340-342 (non-map scalars)

For non-nested, non-map fields:
```rust
merge_toml_fields.push(quote! {
    #field_ident: other.#field_ident.or(self.#field_ident),
});
```

**Semantics of `Option::or()`:**
- `other.or(self)` returns:
  - `Some(other_val)` if `other` is `Some(_)` (overlay wins)
  - `self` (which could be `Some(base_val)` or `None`) if `other` is `None` (base inherited)

This means in `merge_toml(base, overlay)`:
- Overlay field absent (`None`) → inherit base field (whether `Some` or `None`)
- Overlay field present (`Some(v)`) → use overlay value regardless of base

**Map fields (lines 323-338):**
```rust
match (self.#field_ident, other.#field_ident) {
    (Some(mut base), Some(over)) => {
        for (k, over_v) in over {
            if let Some(base_v) = base.get(&k).cloned() {
                base.insert(k, ::zbobr_utility::MergeToml::merge_toml(base_v, over_v));
            } else {
                base.insert(k, over_v);
            }
        }
        Some(base)
    }
    (None, over) => over,
    (base, None) => base,
}
```
- Key-by-key merging: matching keys recursively merged, new keys added
- If either side is absent, behavior matches option merge

**Nested struct fields (lines 186-192):**
```rust
match (self.#field_ident, other.#field_ident) {
    (Some(base), Some(over)) => Some(base.merge_toml(over)),
    (None, over) => over,
    (base, None) => base,
},
```
- Recursive: calls `merge_toml()` on nested Toml structs

---

## Real-World Example: StageDefinition

**Location:** zbobr-api/src/config/mod.rs

**Definition (lines 198-222):**
```rust
pub struct StageDefinition {
    pub role: Option<Role>,
    pub call: Option<Pipeline>,
    pub tool: Option<Tool>,
    pub role_prompt: Option<PathBuf>,
    /// None = absent (inherit), Some(vec![]) = explicitly clear
    pub prompts: Option<Vec<PathBuf>>,
    pub on_success: Option<StageTransition>,
    pub on_failure: Option<StageTransition>,
    pub on_intermediate: Option<StageTransition>,
    pub on_no_report: Option<StageTransition>,
}
```

**MergeToml Implementation (lines 269-283):**
```rust
impl MergeToml for StageDefinition {
    fn merge_toml(self, other: Self) -> Self {
        Self {
            role: other.role.or(self.role),
            call: other.call.or(self.call),
            tool: other.tool.or(self.tool),
            role_prompt: other.role_prompt.or(self.role_prompt),
            prompts: other.prompts.or(self.prompts),
            on_success: other.on_success.or(self.on_success),
            on_failure: other.on_failure.or(self.on_failure),
            on_intermediate: other.on_intermediate.or(self.on_intermediate),
            on_no_report: other.on_no_report.or(self.on_no_report),
        }
    }
}
```

**Key comment (lines 210-213):**
```
/// None means absent in config (inherit from base during merging, or no extra prompts at runtime).
/// Some(vec![]) explicitly sets an empty list.
```

**Real test showing three-state behavior (lines 2201-2263):**
Test: `stage_prompts_cleared_by_empty_list_overlay()`
- Base: `prompts: Some(vec![PathBuf::from("/shared/common.md")])`
- Overlay: `prompts: Some(vec![])`  ← explicitly clears!
- Result: `prompts: Some(vec![])` ← empty list, not inherited

This demonstrates the three states:
1. `None` — field absent, inherit from base
2. `Some(vec![...])` — explicit values, use them
3. `Some(vec![])` — explicit empty, clear inherited values

---

## Custom Serde Deserialization Pattern: Secret Type

**Location:** zbobr-utility/src/secret.rs lines 84-113

This is the CLOSEST ANALOG for implementing custom deserialization in this codebase:

```rust
impl<'de> serde::Deserialize<'de> for Secret {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        // Define helper structs for each variant
        #[derive(serde::Deserialize)]
        #[serde(deny_unknown_fields)]
        struct ValueForm {
            value: String,
        }

        #[derive(serde::Deserialize)]
        #[serde(deny_unknown_fields)]
        struct EnvForm {
            env: String,
        }

        // Untagged enum to try both forms
        #[derive(serde::Deserialize)]
        #[serde(untagged)]
        enum Helper {
            Value(ValueForm),
            Env(EnvForm),
        }

        match Helper::deserialize(deserializer)? {
            Helper::Value(f) => Ok(Secret::value(f.value)),
            Helper::Env(f) => Ok(Secret::env(f.env)),
        }
    }
}
```

**Why this pattern works:**
- `#[serde(untagged)]` tries each variant in order during deserialization
- Each variant uses `#[serde(deny_unknown_fields)]` for validation
- Custom logic applied in the `match` arm

**Another example: StageTransition (lines 159-189 in mod.rs):**
Accepts both string shorthand and full table:
```rust
impl<'de> serde::Deserialize<'de> for StageTransition {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(serde::Deserialize)]
        #[serde(deny_unknown_fields)]
        struct FullTransition {
            #[serde(default)]
            next: Option<Stage>,
            #[serde(default)]
            pause: bool,
        }
        #[derive(serde::Deserialize)]
        #[serde(untagged)]
        enum Helper {
            Stage(Stage),           // String shorthand
            Full(FullTransition),   // Full table
        }
        match Helper::deserialize(deserializer)? {
            Helper::Stage(s) => Ok(StageTransition {
                next: Some(s),
                pause: false,
            }),
            Helper::Full(f) => Ok(StageTransition {
                next: f.next,
                pause: f.pause,
            }),
        }
    }
}
```

---

## Where TomlOption<T> Would Fit

**Best location:** `/data/home/skynet/tasks/workspaces/zbobr/task-58/zbobr/zbobr-utility/src/`

Create new file: `toml_option.rs`
- Define `TomlOption<T>` enum
- Implement `Serialize` and `Deserialize` using the helper enum pattern
- Implement `MergeToml` to handle three-state merge semantics
- Optionally implement `Default`, `From<Option<T>>`, `Into<Option<T>>`

**Module structure:**
```
zbobr-utility/src/
├── lib.rs (add: pub mod toml_option; pub use toml_option::TomlOption;)
├── macros.rs
├── secret.rs
└── toml_option.rs  ← NEW
```

**Integration:**
- Exported from `zbobr_utility` so it can be imported as `use zbobr_utility::TomlOption`
- Can be used in generated `*Toml` structs generated by `config_struct` macro
- Macro would emit fields as `TomlOption<T>` instead of `Option<T>`

---

## Macro Generation Flow Summary

1. **Input:** Struct marked with `#[config_struct]` where name ends with "Config"
2. **Generation step 1 (lines 58-60):** Create names for `*Toml`, `*Args`, `*ArgsDerived`
3. **Generation step 2 (lines 94-92):** Iterate all fields, categorize as:
   - Nested (other Config types) → generates nested Args/Toml
   - Path → marked for path resolution
   - Regular scalar → wrapped in Option in Toml
4. **Generation step 3 (lines 503-507):** Generate `*Toml` struct with Option wrappers
5. **Generation step 4 (lines 524-548):** Generate `merge_toml()`, `merge_with_args()`, `resolve_paths()` methods
6. **Generation step 5 (lines 638-652):** Generate `try_into_config()` conversion from Toml to Config
7. **Generation step 6 (lines 654-675):** Generate `Config` trait impl with `build()` method

---

## Build/Conversion Flow

**Path:** TomlStruct → ConfigStruct

1. **Deserialization:** TOML file → `*Toml` struct (via serde)
2. **Path resolution:** `*Toml::resolve_paths()` (lines 540-547 of macro)
3. **Merging:** Multiple files → `merge_toml()` (lines 531-538 of macro)
4. **Conversion:** `*Toml::try_into_config()` (lines 638-652 of macro) → `Config` struct
   - Validates required fields
   - Nested Toml structs recursively converted via `try_into_config()`
   - Collects missing field names, bails if any required fields absent
5. **CLI override:** `Config::build()` (lines 654-675) applies CLI args via `merge_with_args()`

---

## Key Design Insights for TomlOption<T>

1. **Three distinct states are necessary:**
   - `Absent` (TOML field missing) → None on deserialization, triggers inheritance
   - `Some(val)` (TOML field present) → Some value, overrides base
   - `Some(vec![])` (TOML empty list) → Explicitly clear, not inherited

2. **The `.or()` operator is the merge operation:**
   - `overlay.or(base)` implements "overlay wins if present, else inherit base"
   - Works for all scalar Option types automatically
   - Maps and vectors are special-cased with custom merge logic

3. **Serde untagged enum pattern is the proven solution:**
   - Used in `Secret` (value/env variants)
   - Used in `StageTransition` (string vs full struct)
   - Works with `#[serde(deny_unknown_fields)]` on each variant
   - Provides clean match-based dispatch

4. **MergeToml is a marker trait plus behavior:**
   - Trait with single method `merge_toml(self, other) -> Self`
   - Implemented by scalar types (replace wholesale)
   - Implemented by config types (merge fields)
   - Used recursively by the macro in nested/map merging

5. **The macro handles structural merge logic:**
   - For nested Toml structs: recursive `merge_toml()` call
   - For maps: key-by-key with recursive value merge
   - For lists and scalars: wholesale replacement
   - Macro generates the pattern, trait provides the hook

---

## Testing Pattern

**Location:** zbobr-api/src/config/mod.rs lines 2200+

Tests validate both deserialization and merge semantics:
- `stage_prompts_cleared_by_empty_list_overlay()` at line 2202
  - Proves `Some(vec![])` explicitly clears inherited `Some(vec![...])` values
- `role_mcp_missing_deserializes_as_none()` at line 2268
  - Proves TOML absence deserializes as `None`, enabling inheritance

This test pattern should be replicated for `TomlOption<T>`.

# Plan: Unsetting Values in Config Layering

## Goal
When a TOML `Option<T>` field is assigned an "empty" sentinel value (`""`, `[]`, `{}`, `-inf`), the resulting config value should be `None`, not `Some(empty)`. This allows layered configs to "unset" values from lower layers.

## Key Design Decisions

### 1. Introduce `IsConfigEmpty` trait in `zbobr-utility`
A new trait `IsConfigEmpty` with `fn is_config_empty(&self) -> bool`:
- `String`: returns `is_empty()` — `""` is config-empty
- `Vec<T>`: returns `is_empty()` — `[]` is config-empty
- `IndexMap<K,V>` / `HashMap<K,V>`: returns `is_empty()` — `{}` is config-empty
- `f64`: returns `self.is_infinite() && *self < 0.0` — `-inf` is config-empty
- All other primitive types (`u64`, `i64`, `PathBuf`, etc.): returns `false`

Export from `zbobr_utility` alongside `MergeToml`.

### 2. Implement `IsConfigEmpty` for domain types in `zbobr-api`
All types currently used under `Option<T>` in `#[config_struct]` must implement `IsConfigEmpty`:
- `FixedOffsetTz`, `Secret`, `Role`, `Model`, `Executor`, `Pipeline`, etc.: return `false`
- This serves as the **compile-time guarantee** the issue requests: if a new type is added under `Option` in a config struct but doesn't implement `IsConfigEmpty`, the code won't compile

### 3. Modify the `config_struct` macro (in `zbobr-macros`)
In the generated `try_into_config()` method, for every `Option<T>` leaf field, transform the value by filtering config-empty values to `None`:
```
let field_ident = self.field_ident.filter(|v| !v.is_config_empty());
```
This applies only to fields where the config type is `Option<T>` (i.e., `base_is_option.is_some()`). Non-optional fields are unaffected.

### 4. Auto-generate `IsConfigEmpty` for `*Toml` structs (for map-level key removal)
The macro should also derive `IsConfigEmpty` for each `*Toml` struct it generates: a TOML struct is config-empty if all its `Option` fields are `None`. This enables map-level key removal:

In the generated `merge_toml` for map-type fields (IndexMap/HashMap), when merging overlay values, if the overlay value `is_config_empty()`, remove the key from the base map rather than inserting/merging it.

This allows `[roles.worker] = {}` (all fields absent) to remove the `worker` key when overlaying.

### 5. Update tests
- Update existing tests that expect `Some(vec![])` or `Some("")` at the config build level to expect `None` instead
- Add new tests verifying `""` → `None`, `[]` → `None`, `{}` → `None` at the config build level (after `try_into_config()`)
- Add tests verifying that map key removal via empty overlay works

## Analog
The existing `MergeToml` trait in `zbobr-utility` is the closest analog — it's a trait that types implement to declare merge behavior. `IsConfigEmpty` follows the same pattern.

The existing `into_config_setup` code in `zbobr-macros/src/lib.rs` is where the filtering code is inserted.

## Scope Boundaries
- The filtering applies in `try_into_config()`, NOT in TOML deserialization or `merge_toml`. This preserves the existing behavior where `Some(vec![])` in a TOML struct means "explicitly cleared" (important for the overlay semantics).
- `RoleDefinition` and similar manually-defined TOML structs gain `IsConfigEmpty` via the auto-generated impl for `*Toml` types OR via manual impl.

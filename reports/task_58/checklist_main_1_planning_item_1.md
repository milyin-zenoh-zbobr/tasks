Modify the `#[config_struct]` proc macro in `zbobr-macros/src/lib.rs`.

**What changes:**
1. **Toml struct generation** (around line 503-507): When wrapping fields in `Option<_>` for the generated `*Toml` struct, change leaf (non-nested) fields to use `TomlOption<T>` instead of `Option<T>`. Nested section fields (those that are themselves config structs) should remain `Option<NestedToml>`.

2. **Merge logic** (around lines 524-548): Replace `.or()` calls for leaf fields with `.merge()` (the `MergeToml` method). For `TomlOption`, `merge(base, overlay)` returns overlay unless it's `Absent`. Nested struct merging via `merge_toml()` stays unchanged.

3. **Build/conversion** (`try_into_config()`, around lines 638-652): Convert `TomlOption<T>` → `Option<T>` using `into_option()` when building the final `*Config` struct. `ExplicitNone` and `Absent` both become `None`; `Value(T)` becomes `Some(T)`.

4. **Serde attributes**: The generated `*Toml` struct needs `#[serde(default)]` on `TomlOption` fields so absent TOML keys deserialize as `TomlOption::Absent`. Also ensure skip_serializing works correctly for `Absent` variants.

**Why:** The macro is the central point that generates all Toml overlay structs. Changing it here automatically propagates to all `#[config_struct]`-annotated types.

**Key constraint:** Identify which fields are "leaf" (scalar/string/list) vs "nested section" (another config struct). Only leaf fields get `TomlOption`. The macro already distinguishes these — follow the existing pattern for how it decides wrapping.
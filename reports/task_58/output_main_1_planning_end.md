Plan is ready for review. Key points:

1. **New `TomlOption<T>` type** in `zbobr-utility` with three states: `Absent` (inherit), `ExplicitNone` (nan = clear), `Value(T)` (set)
2. **`config_struct` macro** updated to use `TomlOption<T>` in generated `*Toml` structs with three-way merge
3. **Manual types** (`RoleDefinition`, `ProviderDefinition`, `StageDefinition`, `WorkflowToml`) updated with `TomlOption` fields
4. **Minimal consumer impact** — `TomlOption` provides the same read API as `Option` (`.as_ref()`, `.is_some()`, `.map()`, etc.)
5. **Backward compatible** — existing configs without `nan` behave identically
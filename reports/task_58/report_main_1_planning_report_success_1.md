## Plan: TomlOption<T> — NaN values in config

### Rationale
The layered TOML config uses `Option<T>` where `None` = "inherit from base". There's no way to explicitly clear a field. Using TOML's native `nan` literal as a sentinel enables three-state merging without breaking backward compatibility.

### Key design decisions
- **NaN sentinel is safe**: no legitimate config value parses as NaN
- **TomlOption mirrors Option's read API** → minimal consumer churn
- **Nested config sections stay as `Option<NestedToml>`** — only leaf fields get TomlOption
- **Backward compatible**: existing configs without `nan` behave identically

### Chosen analog
- `zbobr-utility/src/secret.rs` (lines 84-113) for custom serde deserialization pattern
- `MergeToml` trait in `zbobr-utility/src/lib.rs` (lines 19-28) for merge semantics
- Existing `.or()` merge pattern in macro-generated code replaced by `.merge()`

### Checklist summary
1. Create `TomlOption<T>` enum in zbobr-utility with custom serde and MergeToml impl
2. Update `config_struct` proc macro to generate TomlOption for leaf fields
3. Update manual config types (RoleDefinition, ProviderDefinition, StageDefinition, WorkflowToml)
4. Fix consumer code (compile-driven, mechanical changes)
5. Add unit tests (serde roundtrip, merge truth table) and integration test (NaN clearing)
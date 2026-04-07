## Plan: TomlOption<T> — Explicit None via NaN in TOML configs

### Problem
The layered TOML config system uses `Option<T>` where absent fields mean "inherit from base". There's no way to explicitly clear a field in an overlay config. Issue #332 proposes using TOML's native `nan` float literal as a sentinel for "explicitly None".

### Design: Three-state enum

```
TomlOption<T> { Absent, ExplicitNone, Value(T) }
```

- **Absent** — field not in TOML, inherit from base during merge
- **ExplicitNone** — `field = nan`, clears base value to None
- **Value(T)** — normal value, overrides base

### Implementation steps

**Step 1: Create `TomlOption<T>` in `zbobr-utility`** (new file `toml_option.rs`)
- Three variants with Default=Absent, custom serde (visitor intercepts `visit_f64` for NaN), merge method, and Option-compatible read API (as_ref, is_some, map, etc.) to minimize consumer changes.

**Step 2: Update `config_struct` proc macro** (`zbobr-macros/src/lib.rs`)
- Generated `*Toml` structs: `Option<T>` → `TomlOption<T>` for leaf fields
- Merge logic: `other.field.or(self.field)` → `other.field.merge(self.field)`
- Build/conversion: `TomlOption` → `Option<T>` in `Config::build`
- Nested section fields remain `Option<NestedToml>` (unchanged)

**Step 3: Update manual types** (`zbobr-api/src/config/mod.rs`)
- `RoleDefinition`, `ProviderDefinition`, `StageDefinition`, `WorkflowToml`: change `Option<T>` fields to `TomlOption<T>`, update `MergeToml` impls to use `.merge()`, update `resolve_paths`

**Step 4: Consumer updates** — minimal due to Option-compatible API on TomlOption. Final `*Config` structs still use `Option<T>`.

**Step 5: Tests** — serde roundtrip, merge truth table (9 combinations), integration test with base+overlay nan clearing.

### Key design decisions
- NaN sentinel is safe: no legitimate config value parses as NaN
- `TomlOption` mirrors `Option` read API → minimal consumer churn
- Nested config sections (`Option<NestedToml>`) unchanged — clearing entire sections is rare
- Backward compatible: existing configs without `nan` behave identically
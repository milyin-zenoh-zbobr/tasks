Add tests to verify the full TomlOption lifecycle.

**Unit tests** (in `toml_option.rs` or a dedicated test module in `zbobr-utility`):
- Serde roundtrip: deserialize TOML with a normal value → `Value(T)`, with `nan` → `ExplicitNone`, with field absent → `Absent`
- Serialize: `Value(T)` produces the value, `ExplicitNone` produces `nan`, `Absent` skips the field
- Merge truth table: test all 9 combinations of (base, overlay) → expected result. Key cases: `(Value, ExplicitNone) → ExplicitNone`, `(Value, Absent) → Value`, `(ExplicitNone, Absent) → ExplicitNone`
- `into_option()` conversion: `Value(T) → Some(T)`, `ExplicitNone → None`, `Absent → None`

**Integration test** (in `zbobr-api` tests or existing config test suite):
- Create a base TOML config with some fields set
- Create an overlay TOML config with `field = nan` for one of those fields
- Merge and verify the field is cleared (becomes `None` in the final Config)
- Verify that other fields are inherited correctly from base

**Why:** The merge truth table is the core correctness guarantee. The integration test ensures the full pipeline (TOML parse → Toml struct → merge → Config build) works end-to-end.

**Analog:** Follow existing test patterns in the config test suite (around line 2202 in mod.rs where empty vec clearing is tested).
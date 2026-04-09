## Proposed Plan

**Problem:** `zbobr init` generates a `zbobr.toml` that omits all optional fields. Users can't discover available config options without reading source code.

**Solution:** 

1. **New `zbobr generate-config` command** — prints a complete example config to stdout (or a file via `--output`), no workspace creation. Handled before config loading, like `Init`.

2. **Enhanced config generation in `init.rs`** — add `generate_example_config_toml()` that:
   - Uses existing `default_config_toml()` for the set/required fields
   - Post-processes the serialized TOML with `toml_edit` to inject commented-out lines for optional/absent fields with their default values
   - Adds field-level doc comments as TOML `# comment` lines above each field

3. **Update `zbobr init`** — use the same enhanced generator so both commands produce consistent output.

**Key files to change:**
- `zbobr/src/commands.rs` — add `GenerateConfig` variant
- `zbobr/src/main.rs` — handle `GenerateConfig` before config loading
- `zbobr/src/init.rs` — add `generate_example_config_toml()`, update `init_workspace()`

**Approach for commented-out fields:** Use `toml_edit` item decorations (`.decor_mut().set_prefix()`) to prepend `# field = default_value\n` before adjacent fields in each config section. The list of optional fields and their defaults is enumerated in `init.rs`.

**No macro changes needed** — this is a straightforward enhancement to the existing manual config-generation code in `init.rs`.
The plan is ready for review. Here's a summary:

**Goal:** Make `zbobr` config files self-documenting by showing optional fields as commented-out lines with default values.

**Changes:**
1. **New `zbobr generate-config` command** — prints a complete example `zbobr.toml` to stdout (or `--output <path>`), with no workspace creation needed. Like `Init`, it runs before config loading.
2. **`generate_example_config_toml()` in `init.rs`** — builds on the existing `default_config_toml()`, then uses `toml_edit` decorations to inject `# optional_field = default_value` comment lines for absent optional fields.
3. **`zbobr init` updated** — uses the same enhanced generator for consistency.

**Files changed:** `commands.rs`, `main.rs`, `init.rs` — no macro changes needed.
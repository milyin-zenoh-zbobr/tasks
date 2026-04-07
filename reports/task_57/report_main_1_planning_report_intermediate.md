## Plan: `zbobr config` command

### Problem
Issue #311 requests a `config` subcommand that prints the current effective configuration as valid, human-readable TOML — merging all config files into a single view. The same `toml_edit` formatting used by `init.rs` (for inline stage/provider/tool tables) must be reused.

---

### Chosen analog
`init.rs` / `init_workspace` — same struct, same serialization pattern (serialize `RootConfigToml` → `toml::to_string_pretty` → `toml_edit` → `inline_stage_tables` + `inline_dispatcher_tables`).

---

### Architecture

#### 1. Extract shared formatting helper in `init.rs`
The three-line pattern in `init_workspace`:
```
pretty = toml::to_string_pretty(&config)
doc = pretty.parse()
inline_stage_tables(&mut doc); inline_dispatcher_tables(&mut doc);
```
Extract into a `pub(crate) fn format_config_as_toml(config: &RootConfigToml) -> anyhow::Result<String>` function in `init.rs`. Both `init_workspace` and the new command will call it.

#### 2. Add `Config` variant to `Command` enum in `commands.rs`
```
/// Show the resolved configuration as a single merged TOML file
Config,
```
No arguments needed.

#### 3. Handle `Config` early in `main.rs` (before backends)
Mirror the `Init` early-exit pattern — after loading and merging `root_toml` from files (but before building backends), check if the command is `Config` and:
- Call `init::format_config_as_toml(root_toml.as_ref().unwrap_or_default())` (falling back to an empty/default config if no files found)
- Print the resulting TOML to stdout
- Return `Ok(())`

This avoids threading config state through all the `run()` functions.

#### 4. Note on CLI arg overrides
CLI argument overrides (`cli.settings`) are *not* included in the output — they are temporary one-off flags, not part of the config file. The `config` command shows what the config *files* contain, merged into one view.

---

### Files changed
- `zbobr/src/init.rs` — extract `format_config_as_toml` helper (pub(crate))
- `zbobr/src/commands.rs` — add `Config` variant
- `zbobr/src/main.rs` — handle `Config` early (after config loading, before backends)

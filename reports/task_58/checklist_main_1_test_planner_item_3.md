# Test: `config_struct` macro-generated `*Toml` structs handle `nan` correctly

## Location
`zbobr-executor-copilot/src/config.rs` or `zbobr-executor-claude/src/config.rs` — add a `#[cfg(test)] mod tests` block.

## What to test
The `config_struct` macro now generates `TomlOption<T>` fields (for non-map types) in the derived `*Toml` struct. There are no tests verifying that the macro-generated code handles `nan` correctly end-to-end. This is important because the macro path is different from the manually-written config types already tested.

Test that:
1. A `config_struct`-generated `*Toml` struct deserializes a field set to `nan` as `TomlOption::ExplicitNone`.
2. After `merge_toml`, ExplicitNone clears the base value.
3. The `build()` method correctly handles the ExplicitNone case (falls through to default).

For `ZbobrExecutorCopilotToml`, the only field is `copilot_github_token: TomlOption<Secret>`, which is a bit complex. A simpler choice is `ZbobrExecutorClaudeToml` or a fresh `config_struct` test in `zbobr-macros` (or use the dispatcher's `ZbobrExecutorConfig` which is nested).

## Suggested test names
- In `zbobr-executor-claude/src/config.rs`:
  - `config_struct_generated_toml_nan_produces_explicit_none`
  - `config_struct_generated_toml_merge_nan_clears_base`

## Why this matters
The macro generates code for many crates. A bug in the `use_toml_option` branch or `merge_toml_fields` code generation would not be caught by the existing consumer-level tests (which test manually-written types).

## Implementation sketch
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_struct_generated_toml_nan_produces_explicit_none() {
        // Use a simple scalar field from ZbobrExecutorClaudeToml
        // (e.g. model or timeout — check actual field names)
        let toml_str = r#"model = nan"#;
        let parsed: ZbobrExecutorClaudeToml = toml::from_str(toml_str).unwrap();
        assert_eq!(parsed.model, zbobr_utility::TomlOption::ExplicitNone);
    }

    #[test]
    fn config_struct_generated_toml_merge_nan_clears_base() {
        let base_str = r#"model = "claude-opus-4-5""#;
        let overlay_str = r#"model = nan"#;
        let base: ZbobrExecutorClaudeToml = toml::from_str(base_str).unwrap();
        let overlay: ZbobrExecutorClaudeToml = toml::from_str(overlay_str).unwrap();
        let merged = base.merge_toml(overlay);
        assert_eq!(merged.model, zbobr_utility::TomlOption::ExplicitNone);
        assert!(merged.model.into_option().is_none());
    }
}
```

Note: Adjust field names to match the actual fields in `ZbobrExecutorClaudeToml` or `ZbobrExecutorCopilotToml`. Check `zbobr-executor-claude/src/config.rs` for available fields.

# Test: `WorkflowToml.prompts_dir` cleared by `nan`

## Location
`zbobr-api/src/config/mod.rs` — in the existing `#[cfg(test)] mod tests` block.

## What to test
`WorkflowToml.prompts_dir` is now `TomlOption<PathBuf>`. Setting it to `nan` in a TOML overlay should:
1. Parse as `ExplicitNone`.
2. After merge, clear the base prompts_dir (ExplicitNone wins over base Value).
3. After `try_into_config()`, `WorkflowConfig.prompts_dir` is `None`.

There are no existing tests for this field with ExplicitNone.

## Test names
- `workflow_prompts_dir_nan_in_overlay_clears_base`
- `workflow_prompts_dir_nan_resolves_to_none_in_config`

## Implementation sketch
```rust
#[test]
fn workflow_prompts_dir_nan_in_overlay_clears_base() {
    let base_toml = r#"prompts_dir = "/some/dir""#;
    let overlay_toml = r#"prompts_dir = nan"#;

    let base: WorkflowToml = toml::from_str(base_toml).unwrap();
    let overlay: WorkflowToml = toml::from_str(overlay_toml).unwrap();
    let merged = base.merge_toml(overlay);

    assert_eq!(merged.prompts_dir, TomlOption::ExplicitNone);
    // into_option() must return None
    assert!(merged.prompts_dir.into_option().is_none());
}

#[test]
fn workflow_prompts_dir_nan_resolves_to_none_in_config() {
    let toml_str = r#"prompts_dir = nan"#;
    let workflow_toml: WorkflowToml = toml::from_str(toml_str).unwrap();
    // try_into_config converts ExplicitNone → None
    let config = workflow_toml.try_into_config().unwrap();
    assert!(config.prompts_dir.is_none());
}
```

# Test: Stage transition fields cleared by `nan` in TOML overlay

## Location
`zbobr-api/src/config/mod.rs` — in the existing `#[cfg(test)] mod tests` block.

## What to test
`StageDefinition.on_success`, `on_failure`, `on_intermediate`, `on_no_report` are all now `TomlOption<StageTransition>`. Setting them to `nan` in a TOML overlay should:
1. Parse as `ExplicitNone` (TOML deserialization).
2. After merge, clear the base transition (result = ExplicitNone, not the base's Value).
3. `on_success()` / `on_failure()` etc. return `None` (since `as_option()` collapses ExplicitNone → None).

There are currently no tests for the ExplicitNone case for transitions. The existing tests only verify `Value` round-trips and TOML parsing of normal transition values.

## Test names
- `stage_on_success_nan_in_overlay_clears_base_transition`
- (Optionally) `stage_on_failure_nan_in_overlay_clears_base_transition`

## Implementation sketch
```rust
#[test]
fn stage_on_success_nan_in_overlay_clears_base_transition() {
    let base_toml = r#"
[pipelines.main.stages.working]
on_success = "reviewing"
"#;
    let overlay_toml = r#"
[pipelines.main.stages.working]
on_success = nan
"#;
    let base: WorkflowToml = toml::from_str(base_toml).unwrap();
    let overlay: WorkflowToml = toml::from_str(overlay_toml).unwrap();

    let merged = base.merge_toml(overlay);
    let stage = merged
        .pipelines.as_ref().unwrap()[&Pipeline::Main]
        .stage(&Stage::from("working")).unwrap();

    // ExplicitNone should clear the inherited on_success transition
    assert_eq!(stage.on_success, TomlOption::ExplicitNone);
    assert!(stage.on_success().is_none(),
        "nan on_success must produce None at runtime, got: {:?}", stage.on_success());
}
```

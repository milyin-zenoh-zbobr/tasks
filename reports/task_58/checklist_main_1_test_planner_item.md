# Test: `prompt_files_for_stage` — role-level `prompt = ExplicitNone`

## Location
`zbobr-dispatcher/src/prompts.rs` — in the existing `#[cfg(test)] mod tests` block.

## What to test
When `stage_def.role_prompt = Absent` (no stage-level override) and the role definition's `prompt` field is `ExplicitNone`, the function should return no files — not inherit anything.

The existing tests cover:
- `Absent` + role has a `Value` prompt → inherits role prompt ✓
- `ExplicitNone` stage prompt → blocks role fallback ✓
- `Value` stage prompt → overrides role ✓

Missing:
- `Absent` + role has `ExplicitNone` prompt → **no file returned** (role deliberately cleared its own prompt)

## Test name
`prompt_files_for_stage_absent_stage_prompt_role_prompt_explicit_none`

## Implementation sketch
```rust
#[test]
fn prompt_files_for_stage_absent_stage_prompt_role_prompt_explicit_none() {
    // Role's prompt is explicitly cleared (ExplicitNone), stage doesn't override.
    let workflow = make_workflow_with_role_prompt("worker", None); // role prompt = Absent
    // Manually craft a workflow with role.prompt = ExplicitNone instead
    // (use the helper that sets RoleDefinition.prompt = TomlOption::ExplicitNone)
    let stage = StageDefinition {
        role: Some("worker".to_string().into()).into(),
        role_prompt: zbobr_utility::TomlOption::Absent,
        ..Default::default()
    };
    // ... set up workflow so role_def.prompt = TomlOption::ExplicitNone
    let files = prompt_files_for_stage(&stage, &workflow);
    assert!(
        files.is_empty(),
        "ExplicitNone at role level should produce no prompt files; got: {files:?}"
    );
}
```

Note: You may need to add a helper `make_workflow_with_role_prompt_explicit_none` or extend the existing one to accept `TomlOption<PathBuf>` directly.

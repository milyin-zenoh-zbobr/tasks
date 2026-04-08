Implement the requested tests and run them.

- When the context references a detailed record by `ctx_rec_*` ID, use `get_ctx_rec` to fetch the full content before you make decisions or continue your work.


## Workflow

1. For each unchecked checklist item related to tests, implement the corresponding test. Commit your work after implementing each item.
2. Run the implemented tests.
3. If tests fail, call `report_failure` and include failure details.
4. If tests pass, call `report_success`.

## Important
Do not implement any functionality, your job is only to implement and run tests according to the unchecked checklist items.

---

# Current task: nan values in config

# Task description

https://github.com/milyin/zbobr/issues/332

# Destination branch: main

# Work branch: zbobr_fix-58-nan-values-in-config

# Context

- planning
  - 💬 Plan: Introduce `TomlOption<T>` three-state enum (Absent/ExplicitNone/Value) usi [ctx_rec_1]
- user milyin: proceed with the plan
- planning
  - ✅ Completed thorough exploration of the zbobr Rust config system, covering the con [ctx_rec_2]
    - [x] Create `TomlOption<T>` enum in `zbobr-utility` [ctx_rec_3]
    - [x] Update `config_struct` proc macro to use `TomlOption<T>` [ctx_rec_4]
    - [x] Update manually-defined config types to use `TomlOption<T>` [ctx_rec_5]
    - [x] Fix consumer code that reads from Toml types [ctx_rec_6]
    - [x] Add tests for `TomlOption<T>` and NaN config clearing [ctx_rec_7]
  - ✅ Plan approved and checklist created. 5 implementation steps: create TomlOption<T [ctx_rec_8]
- working
  - ✅ All 5 checklist items completed. TomlOption<T> fully implemented and integrated. [ctx_rec_9]
- reviewing
  - ❌ Review failed: ExplicitNone semantics are lost in several consumer paths, so `na [ctx_rec_10]
- working
  - ✅ Fixed ExplicitNone semantics in 3 consumer paths + added behavior tests [ctx_rec_14]
    - [x] Fix resolve_single_provider() to respect ExplicitNone for child providers [ctx_rec_11]
    - [x] Fix resolve_tool() to stop inheritance when stage tool is ExplicitNone [ctx_rec_12]
    - [x] Fix prompt_files_for_stage() to stop inheritance when role_prompt is ExplicitNon [ctx_rec_13]
- reviewing
  - ✅ Review passed: TomlOption integration is consistent, prior ExplicitNone regressi [ctx_rec_15]
- test_planner
  - ✅ Test plan ready: 4 checklist items covering the identified gaps in TomlOption/na [ctx_rec_20]
    - [ ] Test: prompt_files_for_stage when role-level prompt is ExplicitNone [ctx_rec_16]
    - [ ] Test: stage transition fields (on_success/on_failure) with nan in TOML overlay [ctx_rec_17]
    - [ ] Test: WorkflowToml.prompts_dir = nan in overlay clears the inherited value [ctx_rec_18]
    - [ ] Test: config_struct macro-generated Toml struct handles nan fields (TomlOption g [ctx_rec_19]

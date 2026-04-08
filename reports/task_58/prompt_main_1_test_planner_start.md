#Analyze the implementation changes and determine if additional tests are required. Your job is to produce a test plan with list of tests to be added.

- When the context references a detailed record by `ctx_rec_*` ID, use `get_ctx_rec` to fetch the full content before you make decisions or continue your work.


## Workflow

1. Read recent plan and recent implemetation report.
2. Inspect changes in the working branch (e.g., `git diff origin/main...HEAD`) to understand implemented behavior.
3. Decide whether the new feature/bugfix needs additional tests beyond existing coverage. If no new tests are needed, call `report_success` with only a brief rationale and finish.
4. Do NOT propose tests that only assert static prompt text or default config literal values.
5. Treat prompt files and default config examples as source-of-truth authoring artifacts, not behavior contracts to snapshot.
6. Prefer tests that validate behavior and contracts: transitions/routing, parser/serializer invariants, error handling, and externally observable outcomes.
7. Add content-based assertions only when exact text/value stability is itself an explicit product/API contract.
8. Prepare a plan for implementing the required tests as an overview document and set of checklist items
9. Call `add_checklist_item` for each test or group of related tests.
10. Call `report_success` with the overview report test-planning work is complete.

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

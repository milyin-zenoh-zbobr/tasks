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

# Current task: prompts should be hash

# Task description

https://github.com/milyin/zbobr/issues/328


# Destination branch: main

# Work branch: zbobr_fix-55-prompts-should-be-hash

# Context

- planning
  - ✅ Comprehensive analysis of prompt structure in zbobr Rust project. Found current [ctx_rec_1]
  - 💬 Plan: Replace prompt arrays with IndexMap hashes at three config levels (workflo [ctx_rec_2]
- user milyin: update the plan accordingly to changed task decription
- planning
  - ✅ Comprehensive analysis of TomlOption type and its usage in zbobr config system c [ctx_rec_3]
  - 💬 Updated plan: use IndexMap&lt;String, TomlOption&lt;PathBuf&gt;&gt; for prompts [ctx_rec_4]
- user milyin: proceed with the plan
- planning
  - ✅ Plan approved and checklist items created for prompts-should-be-hash implementat [ctx_rec_10]
    - [x] Update config structs to use IndexMap<String, TomlOption<PathBuf>> for prompts [ctx_rec_5]
    - [x] Update resolve_paths for all three structs to iterate map values [ctx_rec_6]
    - [x] Rewrite prompt_files_for_stage() to use three-level map merge [ctx_rec_7]
    - [x] Update default config in init.rs to use named prompt slots [ctx_rec_8]
    - [x] Update tests for new prompts map structure [ctx_rec_9]
- working
  - ✅ Replaced prompt arrays/single fields with named IndexMap slots. All tests pass. [ctx_rec_11]
- reviewing
  - ❌ Review failed: prompt-slot merge reorders prompts and default config now reverse [ctx_rec_12]
- working
  - ✅ Fixed prompt-slot merge order: in-place update preserves key position; default w [ctx_rec_16]
    - [x] Fix merge_prompt_maps() to preserve key order using in-place update instead of s [ctx_rec_13]
    - [x] Fix prompt_files_for_stage() to use in-place update merge (same fix as merge_pro [ctx_rec_14]
    - [x] Fix default_workflow() to seed main=nan before task so roles override main witho [ctx_rec_15]
- reviewing
  - ✅ Review passed: prompt-slot hash implementation now preserves order, matches the [ctx_rec_17]

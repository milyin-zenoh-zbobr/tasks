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

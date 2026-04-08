# Prompt Order Fix

## Issues addressed (from review ctx_rec_12)

1. **`merge_prompt_maps()` reordered keys** (`zbobr-api/src/config/mod.rs:27-35`)  
   Replaced `shift_remove(k)` + `insert(k, merged)` with `get_mut(k)` in-place update. Existing keys now stay at their original position; new keys are appended.

2. **`prompt_files_for_stage()` duplicated the same bug** (`zbobr-dispatcher/src/prompts.rs:215-233`)  
   Applied the same `get_mut` in-place fix to the role-merge and stage-merge loops.

3. **Default workflow only had `task` at workflow level** (`zbobr/src/init.rs:615-618`)  
   Changed `workflow_prompts` to seed both `("main", ExplicitNone)` and `("task", task.md)` in that order. Now when any role overrides `main`, the merge updates it in-place and the final order is `[main, task]` — matching the old `role_prompt → stage prompts` behavior.

4. **Added order-preservation test**  
   `prompt_files_for_stage_preserves_slot_order` in `zbobr-dispatcher/src/prompts.rs` asserts that workflow `{main:nan, task:task.md}` + role `{main:worker.md}` yields `[worker.md, task.md]`.

All 138+ tests pass.
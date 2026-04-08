All three review issues have been fixed and committed:

1. **`merge_prompt_maps()`** — replaced `shift_remove` + `insert` with `get_mut` in-place update to preserve key order
2. **`prompt_files_for_stage()`** — same fix applied to the duplicate merge logic
3. **`default_workflow()`** — workflow-level prompts now seed `main = nan` before `task`, so roles override `main` in-place and the resolved order is always `[main, task]`
4. **New test** — `prompt_files_for_stage_preserves_slot_order` asserts the correct `[worker.md, task.md]` order
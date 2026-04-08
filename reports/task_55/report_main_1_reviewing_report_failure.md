Overall assessment: the new hash-based prompt model is mostly aligned with the plan and the chosen analog (`TomlOption` + `IndexMap`), but there is a correctness issue in the merge/order behavior that changes the effective prompt text.

Analog consistency
- The analog choice was appropriate: using `TomlOption` for three-state values and `IndexMap` for ordered prompt slots matches existing config patterns.
- However, the implementation does not preserve the old prompt ordering contract. In the previous design, `role_prompt` was always loaded before stage `prompts`, so the role's main instruction came first. The new design should preserve that equivalent ordering via named slots, but currently it does not.

Findings

1. Prompt-slot merging reorders overridden keys, which changes prompt concatenation order.
   - In `zbobr-api/src/config/mod.rs:27-35`, `merge_prompt_maps()` uses `shift_remove()` followed by `insert()`. In `IndexMap`, that removes the existing key and reinserts it at the end, so any overridden inherited slot moves later in the final order.
   - `zbobr-dispatcher/src/prompts.rs:215-233` duplicates the same merge pattern for role/stage prompt resolution, so the runtime prompt order is also reordered there.
   - This conflicts with the planned behavior that workflow slot order should carry through inheritance, and it breaks parity with the old analog where the main role prompt came before additional prompts.
   - Concrete example: with workflow prompts `{ main = nan, task = "task.md" }` and role prompts `{ main = "worker.md" }`, the current merge yields `task.md, worker.md` instead of `worker.md, task.md`.

2. The default workflow config now bakes in the wrong order for every normal stage.
   - In `zbobr/src/init.rs:615-618`, the workflow-level defaults only define the `task` slot.
   - In `zbobr/src/init.rs:475-480` and the role definitions below it, each role adds `main` only at the role level.
   - Because `prompt_files_for_stage()` starts from workflow prompts and then inserts role prompts afterward, all default stages resolve to `task.md` before `<role>.md`. That is a behavior change from the previous implementation in `origin/main`, where `role_prompt` was added first and stage prompt files were appended after it.

Why this matters
- Prompt order is semantically important: these files are concatenated verbatim in `load_prompts()`, so reversing them changes the instructions sent to the executor.
- The regression is subtle and currently untested: the new tests cover inheritance/clearing but not slot-order preservation.

Suggested fix
1. Preserve key position when overriding an existing slot instead of remove+insert reordering it. For example, mutate the existing value in place when the key already exists, and only append when the key is new.
2. Reuse the same merge helper for runtime prompt resolution instead of duplicating the merge algorithm in `prompt_files_for_stage()`.
3. Update `default_workflow()` so the workflow-level prompt map establishes the canonical slot order (for example, seed `main` before `task`, using `nan`/`ExplicitNone` for the inherited-empty default), then let roles override `main` without moving it.
4. Add a behavior-oriented test that asserts final prompt file order for the default workflow and for a workflow+role override case.

Checklist status
- The checked items are close to complete, but the default-config and prompt-resolution items are not fully correct because the resulting prompt order is wrong.

Conclusion
- I cannot approve this as-is because the new prompt hash implementation changes effective prompt ordering and therefore changes runtime behavior.
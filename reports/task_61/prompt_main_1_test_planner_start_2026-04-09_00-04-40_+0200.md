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

# Current task: sync fork

# Task description

https://github.com/milyin/zbobr/issues/343

# Destination branch: main

# Work branch: zbobr_fix-61-sync-fork

# Context

- planning
  - 💬 Plan ready for review: add `auto_sync_fork: bool` config option (default: true) [ctx_rec_1]
- user milyin: go with plan
- planning
  - ✅ Plan approved and checklist ready: add `auto_sync_fork: bool` config (default tr [ctx_rec_4]
    - [x] Add `auto_sync_fork: bool` config field (default true) to ZbobrRepoBackendGithub [ctx_rec_2]
    - [x] Add `maybe_sync_fork` method and call it in `ensure_bare_clone_github` before `g [ctx_rec_3]
- working
  - ✅ Added `auto_sync_fork: bool` config (default true) and `maybe_sync_fork` method [ctx_rec_5]
- reviewing
  - ❌ Found one correctness issue: fork sync failures are swallowed, so auto_sync_fork [ctx_rec_6]
- working
  - ✅ Fixed fork sync error handling: errors from merge-upstream now propagate instead [ctx_rec_7]
- reviewing
  - ❌ Found a blocking issue: new auto_sync_fork field was not propagated to an existi [ctx_rec_8]
- working
  - ✅ Added missing auto_sync_fork field to integration test config constructor [ctx_rec_9]
- reviewing
  - ✅ Review passed: auto_sync_fork implementation matches the approved plan, follows [ctx_rec_10]

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
- test_planner
  - ✅ Test plan ready: 4 unit tests for maybe_sync_fork (1 pure unit + 3 wiremock-base [ctx_rec_16]
    - [ ] Add wiremock to zbobr-repo-backend-github dev-dependencies (workspace + crate Ca [ctx_rec_11]
    - [ ] Unit test: maybe_sync_fork skips all HTTP calls when auto_sync_fork = false [ctx_rec_12]
    - [ ] Unit test: maybe_sync_fork skips merge-upstream for non-fork repos [ctx_rec_13]
    - [ ] Unit test: maybe_sync_fork calls merge-upstream for fork repos and returns Ok [ctx_rec_14]
    - [ ] Unit test: maybe_sync_fork propagates merge-upstream HTTP errors [ctx_rec_15]

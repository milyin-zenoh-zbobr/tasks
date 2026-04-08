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

# Current task: implement transport from fields constructor

# Task description

https://github.com/eclipse-zenoh/zenoh/issues/2554

# Destination branch: main

# Work branch: zbobr_fix-59-implement-transport-from-fields-constructor

# Context

- planning
  - 💬 Plan: Add `Transport::new_from_fields()` constructor gated with `#[zenoh_macros: [ctx_rec_1]
- user milyin: proceed with plan
- planning
  - ✅ Plan approved and checklist created. Approach: add `Transport::new_from_fields() [ctx_rec_4]
    - [x] Add `Transport::new_from_fields()` constructor gated with `#[zenoh_macros::inter [ctx_rec_2]
    - [x] Verify: `cargo build` with `internal` feature, with `internal` + `shared-memory` [ctx_rec_3]
- working
  - ✅ Added `Transport::new_from_fields()` constructor gated with `#[zenoh_macros::int [ctx_rec_5]
- working
  - ✅ All work completed in prior session. Transport::new_from_fields() constructor ad [ctx_rec_6]
- reviewing
  - ✅ Review passed: change is correct, scoped, and consistent with the planned `Trans [ctx_rec_7]
- test_planner
  - ✅ Test plan complete: 2 unit tests needed in zenoh/src/api/info.rs to cover Transp [ctx_rec_10]
    - [ ] Add unit test: new_from_fields stores all fields correctly (with and without sha [ctx_rec_8]
    - [ ] Add unit test: new_from_fields produces Transport equal to Transport::new() for [ctx_rec_9]

# Linter Worker Agent

Fix formatting and linting issues in the code.

- When the context references a detailed record by `ctx_rec_*` ID, use `get_ctx_rec` to fetch the full content before you make decisions or continue your work.

## Access Model

You have access to the task context and the repository:
- The task description, work plan, worker's reports, and context are provided below in this prompt. The full history and checklist are available in the context section.
- Your current working directory is the repository with the work branch checked out
- Use `stop_with_error` only to report technical errors

## Workflow

1. Read the task context and failure reports to identify which formatting and linting issues need to be fixed.
2. **Discover formatting and linting setup** by examining CI and build configuration files:
   - `.github/workflows/` — look for formatting/linting steps (e.g., `cargo fmt --check`, `cargo clippy`, `prettier`, `black`, `gofmt`, `eslint`)
   - `Makefile`, `Cargo.toml`, `package.json`, `pyproject.toml`, or equivalent — identify lint/fmt commands
3. **Run the linting/formatting tools** to confirm which issues remain.
4. **Apply fixes**:
   - Apply tool-based auto-fixes (e.g., `cargo fmt`, `gofmt -w`, `black .`, `prettier --write`)
   - Apply manual fixes for linting warnings/errors that require code changes
5. Call `report_success` if all issues were fixed.
6. Call `report_failure` with details if some issues cannot be fixed.

## Important Notes

- **Only fix formatting and linting** — do not modify logic, tests, or functionality.
- **Do not run tests** — functional testing is handled separately.

---

# Current task: transport from fields

# Task description

Implement https://github.com/eclipse-zenoh/zenoh-c/issues/1263
Temporary point zenoh to repo/branch milyin-zenoh-zbobr:zbobr_fix-59-implement-transport-from-fields-constructor, comment out original links to zenoh/main for easy restore when base PR is merged

# Destination branch: main

# Work branch: zbobr_fix-60-transport-from-fields

# Context

- planning
  - 💬 Plan designed: add Transport C type and from_fields constructor to zenoh-c, gate [ctx_rec_1]
- user milyin: The owned transport type already exists. The only purpose of this task is to make 'zc_' internal function which construct this owned transport object from fields in function arguments. 
- planning
  - ❓ In the current zenoh-c codebase (branch `zbobr_fix-60-transport-from-fields`), I
- user milyin: try again, the fork was not synced
- planning
  - 💬 Plan designed: add `zc_transport_from_fields` to zenoh-c, point Cargo.toml to fo [ctx_rec_3]
- user milyin: name it `zc_internal_transport_from_fields`. 
Go with the plan
- planning
  - ✅ Plan approved: add zc_internal_transport_from_fields to zenoh-c, point Cargo.tom [ctx_rec_6]
    - [x] Point Cargo.toml zenoh deps to milyin-zenoh-zbobr fork [ctx_rec_4]
    - [x] Add `zc_internal_transport_from_fields` to src/info.rs [ctx_rec_5]
- working
  - ✅ Added zc_internal_transport_from_fields to zenoh-c; pointed all zenoh deps to mi [ctx_rec_7]
- reviewing
  - ❌ Review failed: new transport constructor silently coerces invalid whatami values [ctx_rec_8]
- user milyin: There is a condition for shared memory support. When shm is enabled, add additional parameter to function, like it's done in rust
- working
  - ✅ Fixed review issues: explicit whatami match (CLIENT arm instead of wildcard), re [ctx_rec_11]
    - [x] Fix wildcard whatami fallback to use explicit CLIENT match (no silent coercion o [ctx_rec_9]
    - [x] Remove unapproved zc_internal_transport_from_fields_shm function from src/info.r [ctx_rec_10]
- reviewing
  - ❌ is_shm conditional parameter not exposed in C API — user's explicit requirement [ctx_rec_12]
- working
  - ✅ Exposed is_shm parameter in zc_internal_transport_from_fields; regenerated heade [ctx_rec_14]
    - [x] Add `#[cfg(feature = "shared-memory")] is_shm: bool` parameter to `zc_internal_t [ctx_rec_13]
- planning
  - 💬 Header ABI mismatch: is_shm not conditionally guarded — split into two cfg-gated [ctx_rec_15]
- user milyin: make structure `zc_internal_create_transport_options_t` with all parameter fields, `is_shm` is conditional. 
rename `zc_internal_transport_from_fields`  to `zc_internal_create_transport` 
Pass the options structure instead of direct parameters
- planning
  - 💬 Plan: introduce zc_internal_create_transport_options_t struct (is_shm cfg-gated [ctx_rec_16]
- user milyin: proceed with the plan
- planning
  - ✅ Plan approved: introduce zc_internal_create_transport_options_t struct, rename f [ctx_rec_19]
    - [x] Add `zc_internal_create_transport_options_t` struct and rename function to `zc_i [ctx_rec_17]
    - [x] Regenerate `include/zenoh_commons.h` after struct/function rename changes [ctx_rec_18]
- working
  - ✅ Introduced zc_internal_create_transport_options_t struct (is_shm cfg-gated), ren [ctx_rec_20]
- reviewing
  - ✅ All checklist items complete: zc_internal_create_transport_options_t struct intr [ctx_rec_21]
- reviewing
  - ✅ All checklist items complete: zc_internal_create_transport_options_t struct intr [ctx_rec_22]
- test_planner
  - ✅ Test plan complete: 3 tests needed in tests/z_api_info.c for the new zc_internal [ctx_rec_26]
    - [ ] test_zc_internal_create_transport_options_default: verify default values [ctx_rec_23]
    - [ ] test_zc_internal_create_transport_all_whatami: create transport for each whatami [ctx_rec_24]
    - [ ] test_zc_internal_create_transport_drop: verify gravestone state after z_drop [ctx_rec_25]
- test_worker
  - ✅ All 3 tests implemented and passing: default options, all whatami variants, and [ctx_rec_27]
- linting
  - ❌ Formatting/lint checks failed (clang-format violations) [ctx_rec_28]

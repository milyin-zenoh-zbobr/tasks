# Linter Agent

Check code formatting and linting and report any issues found.

- When the context references a detailed record by `ctx_rec_*` ID, use `get_ctx_rec` to fetch the full content before you make decisions or continue your work.

## Access Model

You have access to the task context and the repository:
- The task description, work plan, worker's reports, and context are provided below in this prompt. The full history and checklist are available in the context section.
- Your current working directory is the repository with the work branch checked out
- Use `stop_with_error` only to report technical errors

## Workflow

1. Read the task description and context provided below in this prompt.
2. **Discover formatting and linting setup** by examining CI and build configuration files:
   - `.github/workflows/` — look for formatting/linting steps (e.g., `cargo fmt --check`, `cargo clippy`, `prettier`, `black`, `gofmt`, `eslint`)
   - `Makefile`, `Cargo.toml`, `package.json`, `pyproject.toml`, or equivalent — identify lint/fmt commands
   - Note exact commands and flags used in CI so you run the same checks
3. **Run all formatting and linting checks** identified from CI:
   - Record each command executed and its full output
4. Call `report_success` if all checks pass, or `report_failure` with a detailed list of ALL issues found if any checks fail.

## Important Notes

- **Only check formatting and linting** — do not modify logic, tests, or functionality.
- **Do not fix anything** — fixing is handled by a separate stage.
- **Do not run tests** — functional testing is handled by a separate stage.

---

# Current task: implement connectivity API 2

# Task description

Analyze this branch https://github.com/eclipse-zenoh/zenoh-go/tree/connectivity_api
Make new fix based on it (it's ok to just copy the code)
Required changes:
- make `Transport` and `Link` native go structures like it was done for `TransportEvent` and `LinkEvent`. I.e. there should not be drop here:
```go
	for _, tr := range transports {
		fmt.Printf("  zid: %s, whatami: %s, qos: %v, multicast: %v\n",
			tr.ZId(), tr.WhatAmI(), tr.IsQos(), tr.IsMulticast())
		tr.Drop()
	}
```
- wrap `Transport` in the get links parameters under `option` instead of pointer

To use the the native `Transport`for links filtering use `zc_internal_create_transport` function from https://github.com/eclipse-zenoh/zenoh-c/pull/1265

Temporary replace zenoh-c submodule to one for this branch (milyin-zenoh-zbobr:zbobr_fix-60-transport-from-fields), with easy way to switch it back to main zenoh-c

# Destination branch: main

# Work branch: zbobr_fix-54-implement-connectivity-api-2

# Context

- planning
  - 💬 Plan ready for review: implement connectivity API 2 by making Transport and Link [ctx_rec_1]
- user milyin: in zenoh-c transport is passed for filtering with move semantics, check it, correct the plan
- planning
  - 💬 Plan updated: Transport and Link as pure Go structs, using zc_internal_create_tr [ctx_rec_2]
- user milyin: Proceed with plan
- planning
  - ✅ Plan approved and checklist items created for implementing connectivity API 2 [ctx_rec_10]
    - [x] Update zenoh-c submodule to milyin-zenoh-zbobr/zenoh-c branch zbobr_fix-60-trans [ctx_rec_3]
    - [x] Copy base connectivity API files from upstream connectivity_api branch [ctx_rec_4]
    - [x] Redesign Transport as pure Go struct (no C ownership, no Drop/Clone) [ctx_rec_5]
    - [x] Redesign Link as pure Go struct (no C ownership, no Drop/Clone) [ctx_rec_6]
    - [x] Change Transport filter in options from *Transport to option.Option[Transport] [ctx_rec_7]
    - [x] Implement transport filtering using zc_internal_create_transport with move seman [ctx_rec_8]
    - [x] Update examples and tests: remove Drop() calls, use option.Some for transport fi [ctx_rec_9]
- working
  - ✅ Implemented connectivity API 2: Transport and Link as pure Go structs, option.Op [ctx_rec_11]
- reviewing
  - ✅ All 7 checklist items correctly implemented. Transport and Link are pure Go snap [ctx_rec_12]
- test_planner
  - ✅ Test plan complete: 4 tests identified covering untested code paths in backgroun [ctx_rec_17]
    - [x] TestBackgroundTransportEventsListenerWithHistory: test options != nil branch in [ctx_rec_13]
    - [x] TestBackgroundLinkEventsListenerWithHistoryAndFilter: test options != nil branch [ctx_rec_14]
    - [x] TestLinkEventsListenerTransportFilterForwardEvents: test transport filter on new [ctx_rec_15]
    - [x] TestEmptyTransportsAndLinksLists: verify Transports() and Links() return empty s [ctx_rec_16]
- test_worker
  - 💬 Implemented 4 connectivity tests; blocked on zenoh-c build with zc_internal_crea [ctx_rec_18]
  - ✅ All 4 connectivity tests implemented and passing [ctx_rec_19]
- linting
  - ❌ Formatting check failed: make fmt reported files were updated [ctx_rec_20]
- linter_worker
  - ✅ Fixed all formatting issues: examples/z_info/z_info.go (import order) and zenoh/ [ctx_rec_21]

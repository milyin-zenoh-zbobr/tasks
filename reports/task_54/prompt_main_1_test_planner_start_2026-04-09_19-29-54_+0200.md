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
- user milyin: make `LinkEvent` go structure reuse `Link` and `TransportEvent` reuse `Transport`. Make methods to access `Link` in `LinkEvent` and `Transport` in `TransportEvent`. See how it's implemented in rust: https://github.com/eclipse-zenoh/zenoh/blob/main/examples/examples/z_info.rs : `LinkEvent` have method `link()`, it doesn't repeat `Link`'s API
- planning
  - 💬 Plan: TransportEvent wraps Transport via Transport() method, LinkEvent wraps Lin [ctx_rec_20]
- user milyin: proceed with the plan
- planning
  - ✅ Plan approved: TransportEvent wraps Transport via Transport() method, LinkEvent [ctx_rec_24]
    - [x] Refactor TransportEvent to wrap Transport struct via Transport() accessor [ctx_rec_21]
    - [x] Refactor LinkEvent to wrap Link struct via Link() accessor [ctx_rec_22]
    - [x] Update tests and examples to use Transport() and Link() accessors on events [ctx_rec_23]
- working
  - ✅ Refactored TransportEvent to wrap Transport via Transport() accessor and LinkEve [ctx_rec_25]
- reviewing
  - ✅ All 3 checklist items correctly implemented. TransportEvent wraps Transport via [ctx_rec_26]

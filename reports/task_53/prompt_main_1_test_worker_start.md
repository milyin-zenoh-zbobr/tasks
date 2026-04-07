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

# Current task: implement connectivity API

# Task description

analyze this pr with connectivity api update for zenoh-c:
https://github.com/eclipse-zenoh/zenoh-c/pull/1171
Implement the corresponding api for zenoh-go
In the plan write the detailed zenoh-go connectivity API proposal 

# Destination branch: main

# Work branch: zbobr_fix-53-implement-connectivity-api

# Context

- planning
  - 💬 Connectivity API plan ready for review. Proposes Go bindings for zenoh-c PR #117 [ctx_rec_1]
- user milyin: use equal approaches for Link and Transport, map them both to C structure
- planning
  - 💬 Updated connectivity API plan: Both Transport and Link wrap C owned structures e [ctx_rec_2]
- user milyin: - implement test for connectivity api, use z_api_info.c as a sample
- implement example of connectivity api usage in z_info.go, follow the pattern in z_info.c
- planning
  - 💬 Updated plan with test suite and z_info example extension. Tests modeled on z_ap [ctx_rec_3]
- user milyin: use matching listener as analogy for the transport/link events subscription
- planning
  - 💬 Updated plan: connectivity API using matching listener pattern as primary analog [ctx_rec_4]
- user milyin: approved, proceed with the plan
- planning
  - ✅ Plan approved and checklist created. 5 implementation steps: C bridge additions, [ctx_rec_10]
    - [x] Add Transport and Link C bridge types and callbacks to zenoh_cgo.h/c [ctx_rec_5]
    - [x] Implement Transport type in zenoh/transport.go [ctx_rec_6]
    - [x] Implement Link type in zenoh/link.go [ctx_rec_7]
    - [x] Create connectivity test suite in tests/connectivity_test.go [ctx_rec_8]
    - [x] Extend z_info example with connectivity API output [ctx_rec_9]
- working
  - ✅ All 5 connectivity API checklist items complete. C bridge + transport.go were in [ctx_rec_11]
- reviewing
  - ❌ Review failed: listener events leak owned transport/link objects, and Link optio [ctx_rec_12]
- working
  - ✅ Fixed both review issues: string leak in Link.Group()/AuthIdentifier() and event [ctx_rec_18]
    - [x] Fix Link.Group() and Link.AuthIdentifier() to always drop owned string [ctx_rec_13]
    - [x] Convert TransportEvent to pure Go snapshot to fix memory leak [ctx_rec_14]
    - [x] Convert LinkEvent to pure Go snapshot to fix memory leak [ctx_rec_15]
    - [x] Update tests and example to use new snapshot event API [ctx_rec_16]
    - [x] Build and test to verify fixes [ctx_rec_17]
- reviewing
  - ✅ Review passed: connectivity API matches the approved matching-listener/info-quer [ctx_rec_19]
- test_planner
    - [ ] Extend TestTransportsList and TestLinksList with accessor assertions (WhatAmI, I [ctx_rec_20]
    - [ ] Extend TestTransportEventsListener and TestLinkEventsListener with event snapsho [ctx_rec_21]
    - [ ] Add TestBackgroundLinkEventsListener (mirrors existing TestBackgroundTransportEv [ctx_rec_22]
    - [ ] Add TestTransportClone and TestLinkClone lifecycle tests [ctx_rec_23]
    - [ ] Add TestTransportEventsListenerUndeclare to verify Undeclare() returns no error [ctx_rec_24]
- test_planner
  - ✅ Test plan complete: 6 checklist items covering untested Transport/Link accessors [ctx_rec_31]
    - [ ] TestTransportAccessors: verify WhatAmI, IsQos, IsMulticast, IsShm, Clone on a li [ctx_rec_25]
    - [ ] TestTransportEventAccessors: verify WhatAmI, IsQos, IsMulticast, IsShm fields in [ctx_rec_26]
    - [ ] TestLinkAccessors: verify Src, Dst, Mtu, IsStreamed, Interfaces, Group, Clone on [ctx_rec_27]
    - [ ] TestLinkEventSnapshotFields: verify LinkEvent snapshot fields match synchronous [ctx_rec_28]
    - [ ] TestListenerUndeclare: verify Undeclare() on both TransportEventsListener and Li [ctx_rec_29]
    - [ ] TestBackgroundLinkEventsListener: verify DeclareBackgroundLinkEventsListener del [ctx_rec_30]

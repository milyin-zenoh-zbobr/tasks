I do **not** think the revised plan is ready for implementation yet.

It is clearly better than the previous version: it now covers the transport filter on link-event listeners, the `ZenohType` constraint, `Session.close()` lifecycle wiring, and it has a concrete test matrix. Those were real gaps and they appear to be addressed.

However, after checking the current codebase and the linked issue, there are still two significant problems.

## 1. The proposed public API is still narrower than both the issue and the repository conventions

The plan explicitly chooses a **callback-only** public API for connectivity listeners and justifies that with `MatchingListener` as the precedent. That justification does not hold up against the codebase.

### What the repo actually does today
- `AdvancedPublisher.declareMatchingListener(...)` exposes **callback, handler, and channel** overloads, plus **background** listener variants.
- `AdvancedSubscriber.declareSampleMissListener(...)` does the same: **callback, handler, and channel** overloads, plus **background** variants.
- More generally, this Kotlin binding consistently exposes streaming/event APIs in multiple forms, not callback-only.

Relevant files I checked:
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/AdvancedPublisher.kt`
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/pubsub/AdvancedSubscriber.kt`
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/Callback.kt`
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/handlers/Handler.kt`

### Why this matters
The issue asks to implement the **connectivity API** similarly to the Go binding. The Go reference includes both owned listeners and background listeners for transport and link events. In Kotlin terms, a callback-only API would ship a visibly narrower surface than both the reference implementation and the patterns already present in this repository.

At minimum, the plan needs to do one of these explicitly:
1. include **callback + handler + channel + background** variants for transport/link event listeners, or
2. clearly state that this task is intentionally scoped to a smaller API and justify why that is acceptable for issue #647.

As written, the worker is likely to implement a partial API and only discover later that it is inconsistent with the rest of the binding.

## 2. The “store fields in native structure” requirement is still not reconciled with the plan’s data model

Issue #647 says:
- implement connectivity API similarly to the Go binding
- use a similar approach and **store fields in native structure**

The revised plan instead centers on:
- Kotlin-side snapshot types
- passing primitive transport fields over JNI
- reconstructing a Rust `Transport` via `Transport::new_from_fields()` when a filter is needed

That may be technically workable for filtering, and the `internal` feature in `zenoh-jni/Cargo.toml` does make `Transport::new_from_fields()` available. But the plan still does **not** clearly explain whether the public `Transport` and `Link` objects themselves are:
- pure Kotlin value snapshots, or
- wrappers over native-owned structs with JNI-backed accessors.

That distinction matters because the issue text explicitly calls out the storage strategy, and the proposed design currently reads more like “marshal snapshots and reconstruct when needed” than “store fields in native structure.”

This does not mean the plan must exactly mirror Go internals, but it **does** need to reconcile the task requirement with the chosen Kotlin/JNI design before implementation starts. Otherwise the worker has to guess whether the plan is intentionally diverging from the issue or simply underspecified.

## What I would require before approving the plan

1. **Resolve the API-surface question explicitly**
   - Either add handler/channel/background listener forms, or clearly mark them out of scope with justification tied to issue #647.
   - Do not cite `MatchingListener` as callback-only precedent; the current repo shows the opposite at the public API level.

2. **Resolve the object-representation story explicitly**
   - State whether `Transport` and `Link` are pure Kotlin snapshots or native-backed wrappers.
   - Explain how that satisfies, or intentionally departs from, the issue’s “store fields in native structure” requirement.
   - If the design is “pure Kotlin snapshot + reconstruct native transport only for filters,” say that plainly and justify why it is the right Kotlin/JNI adaptation of the Go approach.

Once those two points are clarified, the rest of the plan looks implementable.
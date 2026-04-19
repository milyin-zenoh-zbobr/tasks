Review result: **approved**.

## Scope reviewed
- Branch diff against `origin/main...HEAD`
- Commit history on the work branch
- Task context records `ctx_rec_1`, `ctx_rec_2`, and `ctx_rec_3`
- Changed file: `examples/examples/z_info.rs`
- Analog/reference implementation in `zenoh/src/api/info.rs`

## Findings
No issues found.

## Analog choice assessment
The plan chose the right analog:
- Stable `z_info` output already uses the pattern `println!(..., info.<method>().await)` for simple session info (`zid`, `routers_zid`, `peers_zid`).
- Unstable-only session inspection already lives inside the existing `#[cfg(feature = "unstable")]` block alongside `transports()` and `links()`.
- `SessionInfo::locators()` itself is documented in `zenoh/src/api/info.rs` with the same direct `println!("{:?}", session.info().locators().await)` usage.

The implementation follows that pattern exactly by adding:
```rust
println!("locators: {:?}", info.locators().await);
```
before the transport listing. This is consistent in style, placement, and API usage.

## Correctness and code quality assessment
- The change is minimal and directly addresses the task requirement: demonstrate `SessionInfo::locators()` in the `z_info` example.
- The new line is correctly gated by the pre-existing `#[cfg(feature = "unstable")]` block, matching the method’s unstable status.
- No unnecessary imports, abstractions, or unrelated edits were introduced.
- There are no compile-time/type-safety concerns in the added code; it uses the existing API directly and idiomatically.
- There are no brittle hardcoded couplings beyond the intentional example label `"locators:"`, which is appropriate for example output.

## Task relevance
All changes in the branch are related to this task. The diff contains only the requested example update.

## Checklist status
I found no remaining unchecked checklist items in the provided task context; the listed implementation item is already completed and matches the code.

## Overall assessment
The implementation is correct, focused, and consistent with the chosen analog and surrounding code style. No follow-up changes are needed.
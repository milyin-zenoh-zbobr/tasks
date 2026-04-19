I reviewed the plan and inspected the codebase to validate its assumptions.

Findings:
- `SessionInfo::locators()` exists in `zenoh/src/api/info.rs`, is marked `#[zenoh_macros::unstable]`, and its docs already demonstrate `session.info().locators().await` printed with `{:?}`.
- `examples/examples/z_info.rs` already groups unstable-only informational output inside a single `#[cfg(feature = "unstable")]` block containing `transports()` and `links()`. Adding a `locators()` print in that block is the right architectural fit.
- The proposed insertion point before the `"\ntransports:"` print is sensible and keeps the output ordered from simple summary info to more detailed transport/link listings.
- No additional imports are needed for the proposed line.
- The suggested verification command is valid from the workspace root: `cargo run --example z_info --features unstable` resolves correctly to the `zenoh-examples` crate.

Assessment:
- Correctness: sound.
- Consistency with existing patterns: sound.
- Direction for implementation: clear enough.
- Risk: very low.

Minor non-blocking note:
- The sample locator output in the plan should be treated as illustrative only; the exact locator string depends on runtime configuration/environment.

Conclusion: the plan is ready for implementation without revision.
# Plan: Add `locators()` demonstration to `z_info` example

## Context
`SessionInfo::locators()` was added in PR #1966 and returns the list of locators the current session is listening on. The method is gated behind `#[zenoh_macros::unstable]`. This task adds a demonstration of its usage to the `z_info` example so users can discover the API.

## File to Modify
- `examples/examples/z_info.rs`

## Change Description
Inside the existing `#[cfg(feature = "unstable")]` block, add a `locators()` call **before** the `println!("\ntransports:")` line (currently line 44).

Insert:
```rust
println!("locators: {:?}", info.locators().await);
```

No new imports are required — `Locator` appears only in the return type; the value is printed via `{:?}` on the collected `Vec<Locator>`.

## Pattern / Analog
Mirrors the existing stable prints for `zid()`, `routers_zid()`, and `peers_zid()` — call method, `.await`, print result. The unstable gating follows the same approach used for `transports()` and `links()`.

## Verification
```bash
cargo run --example z_info --features unstable
```
The output should include a `locators:` line such as:
```
locators: ["tcp/127.0.0.1:7447"]
```

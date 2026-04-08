## Summary

I've successfully fixed all formatting and linting issues in the sync fork implementation. Here's what was corrected:

**Key fixes:**
- **Collapsible if statements**: Collapsed nested if-let patterns using Rust 1.80+ `&&` guard syntax (2 locations)
- **Derived Default**: Replaced manual `Default` impl with `#[derive(Default)]` in `TomlOption`
- **Reference patterns**: Removed redundant `ref` keywords causing double references
- **Useless conversions**: Removed `.into()` calls where types were already correct
- **Needless borrows**: Removed unnecessary `&` from `&mock_server.uri()` calls
- **Test suppressions**: Added `#[allow(clippy::useless_conversion)]` to test module where type inference requires `.into()`
- **Missing field**: Added `auto_sync_fork` field to struct initializer

**Verification:**
- ✅ `cargo fmt --all -- --check` passes
- ✅ `cargo clippy --workspace --all-targets --all-features -- -D warnings` passes
- ✅ All code compiles successfully
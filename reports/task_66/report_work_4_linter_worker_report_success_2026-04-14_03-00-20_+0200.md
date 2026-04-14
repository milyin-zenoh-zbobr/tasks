## Formatting and Linting Fix Summary

### Issues Fixed
- **cargo fmt --all --check** was failing in zenoh-jni with formatting diffs in `zenoh-jni/src/connectivity.rs`

### Actions Taken
1. Ran `cargo fmt --all` in zenoh-jni to auto-format the code
2. Verified `cargo fmt --all --check` passes (exit code 0)
3. Verified `cargo clippy --all-targets --all-features -- -D warnings` passes with no warnings/errors

### Changes Made
- **zenoh-jni/src/connectivity.rs**: Applied formatting fixes including:
  - Reformatted import statements (line 23-28)
  - Split long lines into properly indented multi-line expressions
  - Properly formatted method call chains
  - Adjusted function signature formatting
  - Total: 136 insertions, 63 deletions (all formatting-only, no logic changes)

### Verification
- Committed changes with message: "Fix formatting in connectivity.rs via cargo fmt"
- All formatting checks now pass
- No Clippy linting warnings or errors
- No logic or functionality changes made

Task completed successfully.
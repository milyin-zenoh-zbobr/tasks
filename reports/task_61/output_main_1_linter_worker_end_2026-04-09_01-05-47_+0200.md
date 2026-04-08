All formatting and linting issues have been successfully fixed! ✅

**Summary of fixes:**
- Fixed cargo fmt formatting issues across multiple files (imports, line wrapping, macro formatting)
- Fixed cargo clippy warnings (13+ issues including unnecessary references, useless conversions, collapsible if statements)
- Added missing `auto_sync_fork` field to config initializer
- Both `cargo fmt --all -- --check` and `cargo clippy --all-targets --all-features` now pass cleanly
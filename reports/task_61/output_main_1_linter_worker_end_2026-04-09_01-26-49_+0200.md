All formatting and linting issues have been successfully fixed! Here's what was resolved:

**Formatting Issues:**
- Applied all `cargo fmt` corrections for consistent code style

**Clippy Linting Fixes:**
1. Made `Default` impl for `TomlOption<T>` derivable
2. Collapsed nested if-let statements using `&&` operator (2 locations)
3. Removed unnecessary borrows in pattern matching and method calls
4. Removed useless type conversions (where source and target types were identical)
5. Added missing `auto_sync_fork` field to config structure

Both `cargo fmt --check` and `cargo clippy --all-targets --all-features` now pass cleanly. ✓
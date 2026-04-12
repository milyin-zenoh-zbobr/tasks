## Summary

I've successfully fixed all formatting and linting issues in the zbobr codebase:

### Key Fixes:
1. **Formatting** - Applied `cargo fmt` to fix import ordering and code formatting across all files
2. **Collapsible If Statements** - Combined nested `if let` patterns using `&&` operator (5 locations)
3. **Derivable Impls** - Converted manual `Default` impl to `#[derive(Default)]` on `TomlOption` enum
4. **Needless Borrows** - Removed unnecessary `ref` bindings in pattern matching (2 locations)
5. **Useless Conversions** - Removed redundant `.into()` calls converting `String` to `String` (30+ locations)
6. **Type Annotations** - Added explicit type annotations where needed and allowed clippy lint for test code with complex type inference

### Verification:
✅ `cargo fmt --all -- --check` passes  
✅ `cargo clippy --workspace --all-targets --all-features -- -D warnings` passes  

All changes have been committed to the branch.
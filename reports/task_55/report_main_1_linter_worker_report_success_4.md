## Formatting and Linting Fixes Completed

### Summary
All formatting and linting issues in the prompts-should-be-hash implementation have been resolved. The code now passes both `cargo fmt --check` and `cargo clippy --all-targets --all-features -- -D warnings`.

### Issues Fixed

#### 1. Clippy Derivable Impls Error
**File**: zbobr-utility/src/toml_option.rs
- **Issue**: Manual `Default` impl was redundant and could be derived
- **Fix**: Added `Default` derive to the `TomlOption` enum with `#[default]` attribute on `Absent` variant
- **Lines Affected**: 18-32

#### 2. Useless Conversions in API Config Tests
**File**: zbobr-api/src/config/mod.rs
- **Issues**: Three useless `.into()` conversions on `Option<i32>` priority fields
- **Fixes**:
  - Line 1697: Changed `Some(5).into()` to `Some(5)`
  - Line 2627: Changed `Some(5).into()` to `Some(5)`
  - Line 2652: Changed `Some(1).into()` to `Some(1)`

#### 3. Needless Borrow Patterns
**File**: zbobr-api/src/config/mod.rs
- **Issues**: Two patterns with unnecessary `ref` and dereference
- **Fixes**:
  - Line 933: Removed `ref` and changed `(*tool).clone()` to `tool.clone()`
  - Line 974: Removed `ref` and changed `(*parent_name).clone()` to `parent_name.clone()`

#### 4. Dispatcher Prompts Test
**File**: zbobr-dispatcher/src/prompts.rs
- **Issue**: Useless `.into()` conversion on `Option<String>` tool field (line 137)
- **Fix**: Removed `.into()` call

#### 5. Dispatcher Library Tests
**File**: zbobr-dispatcher/src/lib.rs
- **Issues**: 8 useless conversions across multiple test functions
- **Fixes**:
  - Lines 301: Removed `.into()` on `Some(key.clone())`
  - Lines 598, 620, 783: Removed `.into()` on string keys in provider inserts
  - Line 728, 950: Removed `.into()` on `Some(n)` priority fields

#### 6. Dispatcher Task Tests
**File**: zbobr-dispatcher/src/task.rs
- **Issue**: Three useless `.into()` conversions on tool fields
- **Fix**: Removed all `.into()` calls using sed replacement (lines 949, 1021, 1086)

#### 7. Integration Test Helpers
**File**: zbobr-dispatcher/tests/mcp_integration/abstract_test_helpers.rs
- **Issue**: Useless `.into()` conversion on `Option<StageTransition>` (line 794)
- **Fix**: Changed `Some(StageTransition::pause()).into()` to `Some(StageTransition::pause())`

### Verification Results
✅ `cargo fmt --all -- --check` passes without errors
✅ `cargo clippy --all-targets --all-features -- -D warnings` completes successfully
✅ All 12 formatting/linting errors resolved
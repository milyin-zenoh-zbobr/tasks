Formatting and linting checks run (commands executed):

1) rustfmt check (stable):
   git ls-files '*.rs' | xargs rustfmt --check --config "unstable_features=true,imports_granularity=Crate,group_imports=StdExternalCrate,skip_children=true"

Output (excerpt):
Diff in zenoh/src/api/builders/scouting.rs:21:
 
 use crate::api::{
     handlers::{locked, Callback, DefaultHandler, IntoHandler},
-    scouting::{_scout, Scout},
+    scouting::{Scout, _scout},
 };

Diff in zenoh/src/api/info.rs:556:
 
 #[cfg(all(test, feature = "internal"))]
 mod tests {
-    use super::*;
     use zenoh_protocol::core::WhatAmI;
+
+    use super::*;
 
     #[test]
     fn test_new_from_fields_equals_new_from_peer() {

rustfmt exit: 0 (differences reported)

2) clippy runs (multiple variants):
   - cargo +stable clippy -p zenoh --all-targets --no-default-features -- -D warnings
   - cargo +stable clippy -p zenoh --all-targets -- -D warnings
   - cargo +stable clippy -p zenoh --all-targets --features unstable -- -D warnings
   - cargo +stable clippy -p zenoh --all-targets --features unstable,internal -- -D warnings
   - cargo +stable clippy -p zenoh --all-targets --features unstable,shared-memory -- -D warnings
   - cargo +stable clippy --all-targets --features test -- -D warnings
   - cargo +stable clippy --all-targets --features unstable,test -- -D warnings
   - cargo +stable clippy --all-targets --all-features -- -D warnings

All clippy runs finished with exit code 0 (no warnings reported during the runs performed here).

Notes:
- CI uses rustfmt +nightly with the same config; this run used the locally-available rustfmt (stable) and reported formatting diffs.
- Formatting diffs are in the two files shown above; these must be fixed (apply rustfmt with the CI configuration or run the project's formatting workflow).

Conclusion: Linting (clippy) passed, but formatting failed (rustfmt diffs). Please run rustfmt with the CI configuration (nightly rustfmt + the given config) to fix formatting or apply the formatting changes suggested by rustfmt.

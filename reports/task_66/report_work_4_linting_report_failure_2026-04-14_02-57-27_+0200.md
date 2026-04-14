Commands executed:
1) rustup component add rustfmt clippy
2) (cd zenoh-jni && cargo fmt --all --check)
3) (cd zenoh-jni && cargo clippy --all-targets --all-features -- -D warnings)

Results:
- cargo fmt --all --check (in zenoh-jni) FAILED with diffs. Relevant excerpt:

Diff in zenoh-jni/src/connectivity.rs:23:
     config::WhatAmI,
     handlers::Callback,
     session::{
-        Link, LinkEvent, LinkEventsListener,
-        Session,
-        Transport, TransportEvent, TransportEventsListener,
+        Link, LinkEvent, LinkEventsListener, Session, Transport, TransportEvent,
+        TransportEventsListener,
     },
     Wait,
 };
... (many additional formatting diffs in zenoh-jni/src/connectivity.rs)

Full cargo fmt output shows many stylistic reflows (long lines split, argument lists multiline, chained calls indented). File affected: zenoh-jni/src/connectivity.rs (multiple hunks).

- cargo clippy --all-targets --all-features -- -D warnings (in zenoh-jni) completed successfully (no warnings/errors).

Action required: Run 'cargo fmt --all' in the repository (or apply the formatting changes suggested by cargo fmt) to fix the formatting issues in zenoh-jni/src/connectivity.rs. Re-run 'cargo fmt --all --check' to verify.

Note: No other format/lint steps were found in CI workflows for the Gradle/Java/Kotlin side; CI runs 'gradle jvmTest' but no ktlint/spotless/detekt steps were present. Markdown lint runs in CI for README files but was not executed locally.

If a fuller raw output of cargo fmt is needed, it can be provided on request.

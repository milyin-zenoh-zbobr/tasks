Discovered CI lint commands in .github/workflows/ci.yml:
- cargo fmt --all --check (working-directory: zenoh-jni)
- cargo clippy --all-targets --all-features -- -D warnings (working-directory: zenoh-jni)

Commands executed locally (in repository root):
1) cd zenoh-jni && cargo fmt --all --check
2) cd zenoh-jni && rm -f Cargo.lock && cargo clippy --all-targets --all-features -- -D warnings

Full output (combined):
=== Running: cargo fmt --all --check ===
fmt_exit=0
=== Running: cargo clippy (rm Cargo.lock first) ===
warning: `crate_type` is deprecated in favor of `crate-type` and will not work in the 2024 edition
(in the `zenoh_jni` library target)
    Updating crates.io index
    Updating git repository `https://github.com/eclipse-zenoh/zenoh.git`
       Fetch [                         ]   0.00%, 6.52KiB/s                                                                  Fetch [========>                        ] 1 complete; 80 pending                                                      Fetch [========>                        ] 74 complete; 7 pending                                                      Fetch [===========>                     ] 81 complete; 136 pending                                                    Fetch [===========>                     ] 212 complete; 5 pending                                                     Fetch [===========>                     ] 214 complete; 3 pending                                                     Fetch [===========>                     ] 217 complete; 0 pending                                                     Fetch [==============>                  ] 293 complete; 4 pending                                                     Fetch [=================>               ] 299 complete; 28 pending                                                  Locking 437 packages to latest compatible versions
      Adding android-logd-logger v0.4.4 (available: v0.5.0)
      Adding async-std v1.12.0 (available: v1.13.2)
      Adding clap v3.2.25 (available: v4.6.0)
      Adding flume v0.10.14 (available: v0.12.0)
      Adding generic-array v0.14.7 (available: v0.14.9)
      Adding jni v0.21.1 (available: v0.22.4)
      Adding json5 v0.4.1 (available: v1.3.1)
      Adding uhlc v0.8.2 (available: v0.9.0)
 Downloading 1 crate
 Downloaded tokio v1.52.0
 ... (building many crates) ...
 Finished `dev` profile [unoptimized + debuginfo] target(s) in 39.68s
clippy_exit=0

Result: Both cargo fmt and cargo clippy completed successfully (exit code 0). No formatting or linter errors found.

Notes:
- No Kotlin/Gradle formatting tools (ktlint/spotless/detekt) were found in CI workflows or project files; CI only performs Rust formatting/linting and Gradle unit tests.
- If additional linters should be checked (e.g., ktlint, spotless), provide the expected configuration or CI steps and they will be run similarly.

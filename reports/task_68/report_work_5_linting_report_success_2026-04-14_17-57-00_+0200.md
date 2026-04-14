Commands executed:
1) cd zenoh-jni && cargo fmt --all --check
2) cd zenoh-jni && (if Cargo.lock exists: remove it) && cargo clippy --all-targets --all-features -- -D warnings && restore Cargo.lock

Full output:
Working directory: /data/home/skynet/tasks/base/workspaces/zenoh-java/task-68/zenoh-java/zenoh-jni
=== cargo fmt --all --check ===
=== cargo clippy --all-targets --all-features -- -D warnings ===
warning: `crate_type` is deprecated in favor of `crate-type` and will not work in the 2024 edition
(in the `zenoh_jni` library target)
    Updating crates.io index
    Updating git repository `https://github.com/eclipse-zenoh/zenoh.git`
       Fetch [=====>                           ] 0 complete; 1 pending                                                       Fetch [========>                        ] 80 complete; 1 pending                                                      Fetch [===========>                     ] 93 complete; 124 pending                                                    Fetch [===========>                     ] 214 complete; 3 pending                                                     Fetch [==============>                  ] 217 complete; 80 pending                                                    Fetch [=================>               ] 326 complete; 1 pending                                                     Fetch [====================>            ] 346 complete; 0 pending                                                   Locking 437 packages to latest compatible versions
      Adding android-logd-logger v0.4.4 (available: v0.5.0)
      Adding async-std v1.12.0 (available: v1.13.2)
      Adding clap v3.2.25 (available: v4.6.0)
      Adding flume v0.10.14 (available: v0.12.0)
      Adding generic-array v0.14.7 (available: v0.14.9)
      Adding jni v0.21.1 (available: v0.22.4)
      Adding json5 v0.4.1 (available: v1.3.1)
      Adding uhlc v0.8.2 (available: v0.9.0)
    Checking zenoh_jni v1.9.0 (/data/home/skynet/tasks/base/workspaces/zenoh-java/task-68/zenoh-java/zenoh-jni)
    Building [=======================> ] 488/490: zenoh_jni(test), zenoh_jni                                              Building [=======================> ] 489/490: zenoh_jni                                                               Finished `dev` profile [unoptimized + debuginfo] target(s) in 6.49s

Summary:
- cargo fmt exit code: 0
- cargo clippy exit code: 0

Conclusion: Formatting and linting checks (cargo fmt --all --check and cargo clippy --all-targets --all-features -- -D warnings) succeeded in zenoh-jni. No formatting or lint violations found.

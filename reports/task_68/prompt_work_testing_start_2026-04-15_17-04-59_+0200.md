# Tester Agent

Run comprehensive tests to verify the implementation meets all testing requirements and CI/build standards.

- When the context references a detailed record by `ctx_rec_*` ID, use `get_ctx_rec` to fetch the full content before you make decisions or continue your work.

## Access Model

You have access to the task context and the repository for testing:
- The task description, work plan, worker's reports, and context are provided below in this prompt. The full history and checklist are available in the context section.
- Your current working directory is the repository with the work branch checked out
- Use `stop_with_error` only to report technical errors
- You can send multiple success or failure reports to provide detailed feedback on different aspects.

## Workflow

1. Read the task description, work plan, worker's reports, and context provided below in this prompt.
2. **Independently discover testing infrastructure:**
   - Examine CI and build configuration files (`.github/workflows/`, `Makefile`, `Cargo.toml`, `tox.ini`, `CMakeLists.txt`, or equivalent)
   - Identify test frameworks and commands (cargo test, npm test, pytest, etc.)
   - Identify multiplatform or cross-compilation requirements
   - Document any other automated checks that code must pass (security scans, type checking)
3. **Run comprehensive test suite** matching the project's requirements:
   - Execute all test commands you identified from the CI configuration
   - Record test framework versions, commands executed, and full output
   - Measure code coverage if available
   - Verify all CI requirements are met
4. In case of test failures run the failed tests on the original branch to determine if the failure is due to new changes or existing issues in the codebase.
5. **Document all testing performed:**
   - Test frameworks and versions used
   - All commands executed with full output
   - Test results (passed/failed/skipped counts)
   - Any failures found
   - Code coverage metrics
6. Call `report_success` if all tests pass and all requirements are met, or `report_failure` if any tests fail or requirements are not met. Pass your comprehensive test report as a parameter.

## Important Notes

- **Linting and formatting checks are handled by a separate stage — do not run them here.**
- **Do not modify logic or formatting**: Any substantive code changes must go back to the worker.
- **Comprehensive testing**: Run all test commands discovered from the CI unless they require complex environment configuration. Mention skipped tests in the report.
- **Concise but exhaustive reporting**: Include to the report exact command line of each test executed. In case of error append the extract of test log with the error message.
- **Early termination if necessary**: If some test run shows massive failures indicating a fundamental issue with the implementation, you may stop further testing and make `report_failure` report immediately. Otherwise execute full test suite.

---

# Current task: adjust zenoh-java functionality to zenoh-kotlin

# Task description

It's necessary to make https://github.com/eclipse-zenoh/zenoh-kotlin/ package the thin wrapper for zenoh-java to avoid duplication of JNI code.
Implement it accodingly to this [report](https://github.com/milyin-zenoh-zbobr/tasks/blob/reports/reports/task_69/report_plan_planning_report_success_2026-04-15_02-06-02_+0200.md)
The JNI components necessary for zenoh-kotlin are already done

# Destination branch: main

# Work branch: zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin

# Context

- planning
  - ✅ Revised plan for zenoh-jni-runtime Kotlin module, explicitly fixing all three bl [ctx_rec_9]
- plan_review_adversarial
  - ✅ Plan is sound. The proposed `zenoh-jni-runtime` split matches the current codeba [ctx_rec_10]
- working
  - ✅ Created zenoh-jni-runtime subproject with primitive-only JNI adapters. Moved Zen [ctx_rec_26]
    - [x] Step 1: Create zenoh-jni-runtime Gradle subproject (settings, build.gradle, dire [ctx_rec_11]
    - [x] Step 2: Create ZenohLoad and Target in zenoh-jni-runtime [ctx_rec_12]
    - [x] Step 3: Create callback interfaces in zenoh-jni-runtime (public) [ctx_rec_13]
    - [x] Step 4: Create simple JNI adapter classes (JNISubscriber, JNIQueryable, JNILivel [ctx_rec_14]
    - [x] Step 5: Create JNIConfig and JNIKeyExpr (public ptr) in zenoh-jni-runtime [ctx_rec_15]
    - [x] Step 6: Create JNISession in zenoh-jni-runtime (public externals, advanced metho [ctx_rec_16]
    - [x] Step 7: Create JNIPublisher, JNIQuery, JNIQuerier, JNIScout, JNILiveliness in ze [ctx_rec_17]
    - [x] Step 8: Create new advanced pub/sub adapters in zenoh-jni-runtime [ctx_rec_18]
    - [x] Step 9: Update zenoh-java/build.gradle.kts to depend on zenoh-jni-runtime, remov [ctx_rec_19]
    - [x] Step 10: Remove ZenohLoad/Target from zenoh-java and update Logger.kt [ctx_rec_20]
    - [x] Step 11: Delete old zenoh-java JNI adapter files (all except JNIZBytes.kt) [ctx_rec_21]
    - [x] Step 12: Update zenoh-java facade classes (Config.kt, KeyExpr.kt, Publisher.kt, [ctx_rec_22]
    - [x] Step 13: Update zenoh-java Session.kt to inline callback assembly (was in JNISes [ctx_rec_23]
    - [x] Step 14: Update Zenoh.kt (scouting) and Liveliness.kt and Querier.kt to use runt [ctx_rec_24]
    - [x] Step 15: Build and verify - run gradlew build/test to ensure everything compiles [ctx_rec_25]
- reviewing
  - ❌ Implementation is incomplete: the planned zenoh-jni-runtime split and facade mig [ctx_rec_27]
  - ❌ Additional review note: new advanced session JNI entrypoints use inconsistent se [ctx_rec_28]
- working
    - [x] Fix Rust: change Arc::from_raw + mem::forget in declareAdvancedSubscriberViaJNI [ctx_rec_29]
    - [x] Create zenoh-jni-runtime Gradle subproject: build.gradle.kts, settings.gradle.kt [ctx_rec_30]
    - [x] Update zenoh-java: build.gradle.kts (remove cargo build, add runtime dep), delet [ctx_rec_31]
- working
  - ✅ zenoh-jni-runtime module created and all JNI adapters migrated. zenoh-java now d [ctx_rec_33]
    - [x] Step 14: Update Zenoh.kt, Liveliness.kt, Querier.kt to use runtime JNI primitive [ctx_rec_32]
- reviewing
  - 💬 Runtime split and facade migration look correct overall; ctx_rec_30 and ctx_rec_ [ctx_rec_34]
- working
  - ✅ Added ZenohLoad safeguard to Logger.start() — all checklist items complete [ctx_rec_35]
- reviewing
  - ❌ Review failed: runtime split is mostly correct, but zenoh-jni-runtime’s Android [ctx_rec_36]
- working
  - ✅ Added missing zenoh-jni-runtime/src/androidMain/AndroidManifest.xml to fix Andro [ctx_rec_38]
    - [x] Add missing AndroidManifest.xml to zenoh-jni-runtime/src/androidMain/ [ctx_rec_37]
- reviewing
  - ❌ Review failed: zenoh-jni-runtime now publishes io.zenoh.exceptions.ZError, but z [ctx_rec_39]
- working
  - ✅ Fixed duplicate ZError: deleted zenoh-java's copy, changed runtime dep to api(). [ctx_rec_41]
    - [x] Fix ZError duplicate: delete zenoh-java's ZError.kt and change runtime dep to ap [ctx_rec_40]
- reviewing
  - ❌ Review failed: zenoh-java still owns Android Rust/JNI packaging, so the split is [ctx_rec_42]
- working
  - ✅ Removed Android JNI packaging from zenoh-java. zenoh-jni-runtime is now the sole [ctx_rec_44]
    - [x] Remove Android JNI packaging from zenoh-java/build.gradle.kts: remove Rust Andro [ctx_rec_43]
- reviewing
  - ✅ Review passed: final branch matches the planned zenoh-jni-runtime split, stays c [ctx_rec_45]
- linting
  - ✅ Formatting and lint checks passed: cargo fmt and cargo clippy (zenoh-jni) [ctx_rec_46]

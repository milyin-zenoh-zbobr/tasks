# Linter Agent

Check code formatting and linting and report any issues found.

- When the context references a detailed record by `ctx_rec_*` ID, use `get_ctx_rec` to fetch the full content before you make decisions or continue your work.

## Access Model

You have access to the task context and the repository:
- The task description, work plan, worker's reports, and context are provided below in this prompt. The full history and checklist are available in the context section.
- Your current working directory is the repository with the work branch checked out
- Use `stop_with_error` only to report technical errors

## Workflow

1. Read the task description and context provided below in this prompt.
2. **Discover formatting and linting setup** by examining CI and build configuration files:
   - `.github/workflows/` — look for formatting/linting steps (e.g., `cargo fmt --check`, `cargo clippy`, `prettier`, `black`, `gofmt`, `eslint`)
   - `Makefile`, `Cargo.toml`, `package.json`, `pyproject.toml`, or equivalent — identify lint/fmt commands
   - Note exact commands and flags used in CI so you run the same checks
3. **Run all formatting and linting checks** identified from CI:
   - Record each command executed and its full output
4. Call `report_success` if all checks pass, or `report_failure` with a detailed list of ALL issues found if any checks fail.

## Important Notes

- **Only check formatting and linting** — do not modify logic, tests, or functionality.
- **Do not fix anything** — fixing is handled by a separate stage.
- **Do not run tests** — functional testing is handled by a separate stage.

---

# Current task: throw execptions from java

# Task description

The zenoh-jni-runtime in the common-jni branch (use it as destination) throws exceptions from the Rust code.
This is inconvenient for zenoh-kotlin library (in the different repo) which reuses zenoh-jni-runtime and have to wrap each jni call to runCatching.
The new JNI API functions will follow this pattern:
- their return value should include error variant:
  - negative value for enum ints
  - null for objects/strings
  - integer with negative value instead of bool
  - etc...
- they accept string parameter `error`. In case of error they return error variant value and set `error` string to error message. In case of success `error` stays intact

No exception throwing from `zenoh-jni-runtime` anymore.
No export of error type from `zenoh-jni-runtime`.

Error type export and throwing exception is performed on `zenoh-java` level

# Destination branch: common-jni

# Work branch: zbobr_fix-75-throw-execptions-from-java

# Context

- configuring
  - ✅ destination branch set to common-jni [ctx_rec_1]
- configuring
  - ✅ no destination branch override needed [ctx_rec_2]
- planning
  - ✅ Implementation plan designed for refactoring zenoh-java JNI error handling: repl [ctx_rec_3]
- plan_review_adversarial
  - ❌ Plan is not ready: it leaves JNI/runtime exception paths and required call sites [ctx_rec_4]
- planning
  - ✅ Revised implementation plan covering all throw_exception! paths: adds zbytes/zby [ctx_rec_5]
- plan_review_adversarial
  - ❌ Revised plan is close, but it is still not implementation-ready: it omits the ze [ctx_rec_6]
- planning
  - ✅ Revised implementation plan addressing all ctx_rec_6 blocking issues: added Live [ctx_rec_7]
- plan_review_adversarial
  - ✅ Plan is now sound and implementation-ready. The liveliness blocker is fixed, the [ctx_rec_8]
- working
    - [x] Phase 1: Update errors.rs — add set_error_string helper, remove throw_on_jvm and [ctx_rec_9]
    - [x] Phase 2: Update utils.rs — replace throw_exception! in load_on_close with tracin [ctx_rec_10]
    - [x] Phase 3a: Update Rust config.rs, key_expr.rs, logger.rs, zenoh_id.rs to use erro [ctx_rec_11]
    - [x] Phase 3b: Update Rust session.rs to use error_out pattern (all ~19 exported func [ctx_rec_12]
    - [x] Phase 3c: Update Rust publisher.rs, query.rs, querier.rs, scouting.rs, zbytes.rs [ctx_rec_13]
    - [x] Phase 4a: Delete ZError.kt from zenoh-jni-runtime/src/commonMain/kotlin/io/zenoh [ctx_rec_14]
    - [x] Phase 4b: Update all JNI adapter files in zenoh-jni-runtime to use error_out pat [ctx_rec_15]
    - [x] Phase 5a: Create ZError.kt in zenoh-java/src/commonMain/kotlin/io/zenoh/exceptio [ctx_rec_16]
    - [x] Phase 5b: Update all JNI call sites in zenoh-java to use error-array pattern and [ctx_rec_17]
- working
  - ✅ All JNI error handling refactored: exceptions now thrown from Kotlin, not Rust [ctx_rec_28]
    - [x] Phase 5b: Update zenoh-java JNI call sites to use error-array pattern [ctx_rec_18]
    - [x] Phase 3: Update scouting.rs - add error_out param, return null ptr on error [ctx_rec_19]
    - [x] Verification: build passes, no throw_exception in Rust, no ZError in runtime [ctx_rec_20]
    - [x] Phase 3: Update ext/advanced_subscriber.rs - add error_out params [ctx_rec_21]
    - [x] Phase 4a: Delete ZError.kt from zenoh-jni-runtime [ctx_rec_22]
    - [x] Phase 4b: Update all Kotlin JNI adapter files in zenoh-jni-runtime [ctx_rec_23]
    - [x] Phase 3: Update zbytes.rs - add error_out param, return null jobject on error [ctx_rec_24]
    - [x] Phase 5a: Create ZError.kt in zenoh-java [ctx_rec_25]
    - [x] Phase 3: Update ext/advanced_publisher.rs - add error_out params [ctx_rec_26]
    - [x] Phase 3: Update zbytes_kotlin.rs - add error_out params, return null on error [ctx_rec_27]
- reviewing
  - ❌ Review failed: ZenohId JNI path was left half-migrated, and ZBytes runtime tests [ctx_rec_29]
- working
  - ✅ Fixed ZenohId JNI migration and ZBytes test compilation. All tests pass. [ctx_rec_30]
- reviewing
  - ❌ Review failed: zbytes runtime adapters still use Any? instead of ByteArray?, and [ctx_rec_31]
- working
  - ✅ Fixed zbytes serialize return types (Any? → ByteArray?) and added @Throws(ZError [ctx_rec_32]
- reviewing
  - ❌ Review failed: Java ZBytes tests/examples still call newly checked serialize/des [ctx_rec_33]
- working
  - ✅ Fixed Java ZBytes call sites: added `throws ZError` to all test methods in ZByte [ctx_rec_34]
- reviewing
  - ✅ Review passed: the refactor consistently moves exception creation to zenoh-java, [ctx_rec_35]

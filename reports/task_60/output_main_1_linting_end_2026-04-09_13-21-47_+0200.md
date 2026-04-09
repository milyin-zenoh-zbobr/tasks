Searching the repository for CI workflow and lint configuration (Cargo.toml, .github workflows, CMakeLists) to discover the exact formatting/lint commands used in CI. Running file views and a glob for workflows now.

● Explore(gpt-5-mini) Report intent and discover linters
  │ Read Cargo.toml
  │   └ 137 lines read
  └ List directory .github/workflows
      └ 4 files found

Inspecting CI workflow and Cargo.toml to extract exact formatting and lint commands to run locally. Fetching .github/workflows/ci.yml and full Cargo.toml now.

● Read Cargo.toml
  └ 137 lines read

● Read check-labels.yml
  │ .github/workflows/check-labels.yml
  └ 15 lines read

● Read ci.yml
  │ .github/workflows/ci.yml
  └ 315 lines read

● Read release.yml
  │ .github/workflows/release.yml
  └ 278 lines read

Running the CI lint/format commands (clang-format dry-run, install rustfmt/clippy, cargo clippy, cargo fmt --check) and capturing full output for each.

✗ bash Running command · command: "echo '=== clang-format check ===' if command -v clang-format…", …
  └ "description": Required

● Run clang-format, install rustfmt/clippy, run cargo clippy and cargo fmt --check (shell)
  │ echo '=== clang-format check ==='
  │ if command -v clang-format >/dev/null; then
  │ find include/ src/ tests/ examples/ -type f \( -iname "*.h" -o -iname "*.c" \) -print0 |
  │ xargs -0 clang-format -n -Werror 2>&1 || true
  │ else…
  └ 29 lines...

● Show lint outputs (first chunk) (shell)
  │ sed -n '1,240p' /tmp/copilot-tool-output-1775733342769-k0dh1t.txt
  └ 241 lines...

● Show next chunk of lint outputs (shell)
  │ sed -n '241,480p' /tmp/copilot-tool-output-1775733342769-k0dh1t.txt
  └ 241 lines...

● number lines for locating cargo clippy section (shell)
  │ nl -ba /tmp/copilot-tool-output-1775733342769-k0dh1t.txt | sed -n '1,600p' | sed -n '1,600p'
  └ 13 lines...

● find cargo clippy marker (shell)
  │ grep -n "=== cargo clippy ===" -n /tmp/copilot-tool-output-1775733342769-k0dh1t.txt || true
  └ 2 lines...

● show cargo clippy and later output (shell)
  │ sed -n '1391,1800p' /tmp/copilot-tool-output-1775733342769-k0dh1t.txt
  └ 11 lines...

● show first part of clippy output (shell)
  │ sed -n '1391,1600p' /tmp/copilot-tool-output-1775733342769-k0dh1t.txt
  └ 11 lines...

● Find errors in output (shell)
  │ grep -n "error\:" /tmp/copilot-tool-output-1775733342769-k0dh1t.txt | sed -n '1,200p'
  └ 11 lines...

● Search for warnings/errors/failed in output (shell)
  │ grep -n "warning:\|error:\|failed" /tmp/copilot-tool-output-1775733342769-k0dh1t.txt | sed -n
  │ '1,200p'
  └ 11 lines...

● Retrieve full lint outputs to include in report (shell)
  │ cat /tmp/copilot-tool-output-1775733342769-k0dh1t.txt
  └ 14 lines...

● report_failure (MCP: zbobr) · brief: "Formatting/lint checks failed (clang-format violations)", f…
  └ Report stored

Summary: lint/format checks failed.

- clang-format dry-run reported many -Wclang-format-violations across include/, tests/, and src/ (examples: include/zenoh_memory.h, many tests/*.c).
- rustfmt/clippy were run; full CI-like output captured.

Reproduction commands (from repo root):
- find include/ src/ tests/ examples/ -iname "*.h" -o -iname "*.c" | xargs clang-format -n -Werror
- rustup component add rustfmt clippy
- cargo clippy --all-targets --no-default-features --features unstable,shared-memory -- --deny warnings
- cargo fmt --check -- --config "unstable_features=true,imports_granularity=Crate,group_imports=StdExternalCrate"

Full captured output saved at: /tmp/copilot-tool-output-1775733682849-88dme3.txt

Action: reported failure with detailed output.

--- stderr ---

Total usage est:        0 Premium requests
API time spent:         2m 5s
Total session time:     6m 57s
Total code changes:     +0 -0
Breakdown by AI model:
 gpt-5-mini               527.0k in, 7.6k out, 481.0k cached (Est. 0 Premium requests)
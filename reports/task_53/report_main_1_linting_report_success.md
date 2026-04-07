Scans performed:
- Listed CI workflows: .github/workflows/ci.yml
- Opened Makefile and go.mod
- Searched repository for common lint/format tools

CI formatting command discovered:
- CI job 'fmt' runs: make fmt
- Makefile 'fmt' target uses: GO_FMT=go fmt on ./examples (SRC_DIR)

Commands executed locally:
- make fmt
  - Output: (no formatting changes). go fmt returned exit code 0; no files reported.

Findings:
- No formatting issues found by make fmt (examples directory).
- No other repo-level linters (golangci-lint, staticcheck, etc.) configured in top-level CI for zenoh-go.
- Note: The zenoh-c submodule has its own clang-format and cargo fmt checks in zenoh-c/.github workflows; not run here.

Conclusion: All formatting checks configured in zenoh-go CI passed locally.

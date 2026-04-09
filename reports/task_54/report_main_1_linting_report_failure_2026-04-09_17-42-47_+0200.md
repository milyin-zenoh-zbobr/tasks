Formatting and lint discovery:
- CI workflow (.github/workflows/ci.yml) contains a fmt job that runs: make fmt
- Makefile fmt target runs: go fmt ./examples/...

Commands executed and outputs:
1) Discovery (CI/Makefile/go.mod): (summarized)
   - Found CI fmt job: make fmt
   - Makefile fmt target uses GO_FMT=go fmt and checks ./examples/...

2) Run formatting check (make fmt):
$ make fmt
Output:
Code format was updated:
examples/z_info/z_info.go
make: *** [Makefile:28: fmt] Error 1

Summary:
- Formatting check failed. The Go formatter would change: examples/z_info/z_info.go
- No linters (golangci-lint/staticcheck/etc.) were found in the repository CI steps.

Suggested remediation (do NOT apply here per instructions):
- Run `gofmt -w examples/z_info/z_info.go` or `go fmt ./examples/...` to apply formatting.
- Re-run `make fmt` to verify all formatted files are clean.

Recorded commands run: make fmt

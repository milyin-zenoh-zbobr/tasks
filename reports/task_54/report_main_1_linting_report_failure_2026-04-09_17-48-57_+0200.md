Commands run:
1) Identified CI fmt step in .github/workflows/ci.yml: runs 'make fmt'.
2) Ran: make fmt

Output:
Code format was updated:
examples/z_info/z_info.go
make: *** [Makefile:28: fmt] Error 1

Summary: make fmt failed because examples/z_info/z_info.go is not formatted. No other format/lint steps were found in CI. Please run 'gofmt -w examples/z_info/z_info.go' or 'make fmt' locally to apply formatting, then re-run checks.
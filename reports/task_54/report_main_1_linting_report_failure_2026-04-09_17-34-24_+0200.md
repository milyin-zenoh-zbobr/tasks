Command: make fmt

Exit code: 2

Output:
Code format was updated:
examples/z_info/z_info.go
make: *** [Makefile:28: fmt] Error 1

Explanation: The 'make fmt' target runs 'go fmt ./examples/...'. go fmt changed one file (examples/z_info/z_info.go). To fix, run 'go fmt ./examples/...' or 'make fmt' locally and commit the formatting changes.
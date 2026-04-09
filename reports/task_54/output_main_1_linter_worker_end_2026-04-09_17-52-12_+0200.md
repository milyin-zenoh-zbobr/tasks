✅ **Formatting fixed!** 

The issue was in `examples/z_info/z_info.go` — the import block had incorrect grouping. I reorganized the imports to properly separate standard library imports (`fmt`, `os`, `os/signal`, `strings`, `syscall`) from third-party imports with a blank line between them.

The fix follows Go's standard formatting convention, and `make fmt` now passes without errors.
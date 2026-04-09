## Formatting Fix Summary

### Issue
The file `examples/z_info/z_info.go` had an incorrectly formatted import block where third-party imports were mixed with standard library imports without proper separation.

### Root Cause
Go code formatting convention requires imports to be grouped in two sections:
1. Standard library imports (fmt, os, os/signal, strings, syscall)
2. Third-party imports (github.com/eclipse-zenoh/...)

The blank line separator was in the wrong position, breaking the convention.

### Fix Applied
Reorganized the import statement in `examples/z_info/z_info.go` (lines 17-26) to:
- Keep all standard library imports together (fmt, os, os/signal, strings, syscall)
- Add a blank line separator
- Group all third-party imports together (github.com/eclipse-zenoh/zenoh-go/examples/utils and github.com/eclipse-zenoh/zenoh-go/zenoh)

### Verification
- Ran `make fmt` successfully with no errors or output
- Git diff confirms only the import order was modified
- No code logic or functionality was changed

All formatting checks now pass.
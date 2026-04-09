## Formatting Fix Completed

### Issue Identified
- File: `examples/z_info/z_info.go`
- Problem: Import block had incorrect formatting with misaligned blank lines

### Fix Applied
- Ran `go fmt ./examples/z_info/z_info.go` to apply standard Go formatting rules
- Imports are now properly grouped and sorted

### Verification
- Ran `make fmt` command - passed with no errors
- Go version: go1.22.2 linux/amd64
- All formatting issues resolved

### Files Modified
- `examples/z_info/z_info.go` - import reorganization
## Formatting and Linting Fixes Complete

### Issues Fixed
1. **examples/z_info/z_info.go** - Import ordering
   - Moved custom import `github.com/eclipse-zenoh/zenoh-go/examples/utils` after standard library imports
   - Go convention: standard library imports first, then external imports

2. **zenoh/link.go** - General formatting
   - Applied standard Go formatting rules via gofmt

### Verification
- Ran `gofmt` check on all Go files: ✅ All pass
- Ran `make fmt` target: ✅ Passes with no updates needed
- CI formatting check would pass: ✅ Yes

### Tools Used
- `go fmt` - Built-in Go formatting tool (the official standard for Go code formatting)
- `make fmt` - Custom target defined in Makefile that runs gofmt and fails if changes would be made

All code now conforms to Go's standard formatting rules and is ready for CI/CD.

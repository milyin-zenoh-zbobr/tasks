## Linting Fix Summary

### Issue Fixed
- **File**: zenoh-java/README.md
- **Line**: 165
- **Rule**: MD059 (descriptive-link-text)
- **Problem**: Link text should be descriptive instead of "[here]"

### Change Made
Replaced non-descriptive link text:
```
Before: "or alternatively it can be found [here](https://developer.android.com/ndk/downloads)."
After:  "or alternatively it can be downloaded from the [Android NDK downloads page](https://developer.android.com/ndk/downloads)."
```

### Verification
- Fixed zenoh-java/README.md in the common-jni branch of the submodule
- Committed change in submodule with descriptive commit message
- Updated parent repository submodule reference
- Re-ran markdownlint: 0 errors found in all 4 README.md files

All formatting and linting checks now pass.
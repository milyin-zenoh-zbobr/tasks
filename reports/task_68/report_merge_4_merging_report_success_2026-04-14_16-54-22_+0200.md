## Merge Conflict Resolution Report

### Conflict Resolution
**File:** `zenoh-jni/Cargo.toml`
**Conflict Type:** Version and dependency feature mismatch

### Resolution Details
The conflict arose from divergent versions:
- **HEAD (work branch):** zenoh 1.8.0 with unstable + internal features
- **main (destination):** zenoh 1.9.0 with updated feature configuration

**Resolution Applied:** Accepted the main branch's newer versions (1.9.0) as the canonical state:
- zenoh: 1.9.0 with features = ["unstable", "internal"]
- zenoh-ext: 1.9.0 with features = ["internal"] (removed "unstable" as per main)

### Changes Merged
1. `version.txt`: Updated from 1.8.0 → 1.9.0
2. `zenoh-jni/Cargo.toml`: Resolved version conflict, merged dependency updates
3. `zenoh-jni/Cargo.lock`: Merged lock file changes from main

### Merge Commit
- **Branch:** `zbobr_fix-68-adjust-zenoh-java-functionality-to-zenoh-kotlin`
- **Commit:** `890a05d` with message "chore: merge main branch - resolve version conflicts"
- **Status:** ✅ Complete, working tree clean, ahead of origin/main by 3 commits

### Verification
- All conflict markers removed
- All staged files committed
- Working tree clean
- Merge successfully completed

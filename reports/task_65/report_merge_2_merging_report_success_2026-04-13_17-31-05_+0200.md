## Merge Conflict Resolution Report

### Conflict Overview
A single file had merge conflicts: `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/query/Query.kt`

### Conflict Details
The conflict was a minor whitespace discrepancy between the HEAD and main branches at lines 183-186, specifically an extra blank line after the `acceptsReplies()` function closing brace in the HEAD version.

### Resolution
The conflict was resolved by:
1. Removing all conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
2. Merging the conflicting sections to keep the code intact with appropriate spacing
3. Adding the resolved file to the staging area
4. Completing the merge with a commit message: "chore: merge conflicts resolved"

### Verification
- All conflicts resolved successfully
- Working tree is clean
- Merge commit created: `4c2c9337`
- Branch status: `zbobr_fix-65-implement-connectivity-api-for-zenoh-kotlin` is up to date with no unmerged paths

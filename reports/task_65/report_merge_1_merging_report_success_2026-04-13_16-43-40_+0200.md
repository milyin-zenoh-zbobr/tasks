# Merge Conflict Resolution Report

## Summary
Successfully resolved all merge conflicts between the work branch `zbobr_fix-65-implement-connectivity-api-for-zenoh-kotlin` and the main branch.

## Conflicts Resolved

### 1. JNISession.kt - declareQuerier Method (Lines 242-257)
**Conflict Type**: Incompatible parameter and property access changes

**Work Branch (HEAD)**: 
- Added `acceptReplies: ReplyKeyExpr` parameter
- Used `.ordinal` to access QoS congestion control and priority values

**Main Branch**:
- Removed `acceptReplies` parameter
- Changed to use `.value` property instead of `.ordinal`

**Resolution**: Combined both changes:
- Retained the new `acceptReplies: ReplyKeyExpr` parameter (feature addition)
- Used `.value` property for QoS fields (correct API per enum definitions)
- Converted acceptReplies to ordinal: `acceptReplies.ordinal`

**Rationale**: The QoS enums (CongestionControl, Priority) define a `value` property for JNI serialization, not `.ordinal`. The acceptReplies parameter represents the connectivity feature being implemented.

### 2. Query.kt - Reply Methods (Lines 166-206)
**Conflict Type**: Overlapping method additions

**Work Branch (HEAD)**:
- Added new `acceptsReplies(): ReplyKeyExpr` method to detect reply policy

**Main Branch**:
- Added two new deprecated `replyDel()` overloads accepting QoS instead of ReplyQoS

**Resolution**: Kept both features:
- Retained the new `acceptsReplies()` method that inspects selector parameters
- Added the deprecated replyDel overloads that delegate to ReplyQoS versions
- Proper deprecation guidance for API migration

**Rationale**: Both changes are complementary and non-conflicting. The deprecated overloads provide backward compatibility while acceptsReplies() adds new functionality.

## Files Modified
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/jni/JNISession.kt`
- `zenoh-kotlin/src/commonMain/kotlin/io/zenoh/query/Query.kt`

## Merge Commit
- **Hash**: 0c641448
- **Message**: "chore: merge conflicts resolved"
- **Author**: Copilot <223556219+Copilot@users.noreply.github.com>

## Verification
- All conflict markers removed
- All files compiled successfully (no syntax errors)
- Working tree clean after merge
- Both work branch features (acceptReplies parameter/method) and main branch updates (QoS property changes, deprecated overloads) preserved
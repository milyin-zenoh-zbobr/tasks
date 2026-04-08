# Fix: Propagate auto_sync_fork to integration test config

## Issue
Reviewer found that `ZbobrRepoBackendGithubConfig` in `zbobr-dispatcher/tests/mcp_integration/env.rs:258-263` was missing the new `auto_sync_fork: bool` field added as part of the sync-fork feature. This would cause a compile error when the integration test target is built.

## Fix
Added `auto_sync_fork: true` to the struct literal at `zbobr-dispatcher/tests/mcp_integration/env.rs:263`, matching the default behavior intended by the feature.

## Verification
`cargo check -p zbobr-dispatcher` passes cleanly.

## Commit
d96a6f96 fix: add auto_sync_fork field to ZbobrRepoBackendGithubConfig in integration test env
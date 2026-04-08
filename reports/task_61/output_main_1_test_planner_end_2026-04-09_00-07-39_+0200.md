Test planning is complete. Here's a summary of what was determined:

**4 tests are needed** for the new `maybe_sync_fork` logic in `zbobr-repo-backend-github/src/github.rs`:

| # | Test | Requires |
|---|------|----------|
| 1 | `auto_sync_fork = false` → returns `Ok(())` without any HTTP call | No mock needed |
| 2 | Non-fork repo → skips `merge-upstream` (0 calls to that endpoint) | wiremock |
| 3 | Fork repo → calls `merge-upstream`, returns `Ok(())` | wiremock |
| 4 | Fork repo + `merge-upstream` 422 → propagates `Err(_)` | wiremock (validates the error-propagation bug fix) |

**Prerequisite:** Add `wiremock = "0.6"` to workspace and crate dev-dependencies so octocrab can be pointed at a mock server via `.base_uri(mock_server.uri())`.
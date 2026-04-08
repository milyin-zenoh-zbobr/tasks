# Test planning complete: auto_sync_fork / maybe_sync_fork

## Summary

The implementation added `auto_sync_fork: bool` config and a private `maybe_sync_fork()` method that:
1. Short-circuits when `auto_sync_fork = false`
2. Fetches repo info from GitHub to detect forks
3. Calls `merge-upstream` only for fork repos
4. Propagates errors from merge-upstream (was a bug, now fixed)

No existing tests cover this new logic. Four new tests are planned, with one prerequisite (adding wiremock).

## Checklist items added

- **[ctx_rec_11]** Add wiremock dev-dependency (workspace + crate Cargo.toml) — prerequisite
- **[ctx_rec_12]** Unit test: `auto_sync_fork = false` skips all HTTP calls — no mock server needed
- **[ctx_rec_13]** Unit test: non-fork repo skips merge-upstream — wiremock, asserts 0 calls to merge-upstream endpoint
- **[ctx_rec_14]** Unit test: fork repo calls merge-upstream successfully — wiremock, happy path
- **[ctx_rec_15]** Unit test: merge-upstream error propagates as `Err(_)` — validates the error-propagation bug fix

## Implementation notes

All tests go in `mod tests` in `zbobr-repo-backend-github/src/github.rs`. Private types (`GitHubRepo`, struct fields) are accessible there. For wiremock tests, octocrab must be built with `.base_uri(mock_server.uri())` and the backend struct constructed directly to inject the custom client.

Verification: `cargo test -p zbobr-repo-backend-github`
Add a `#[tokio::test]` in `mod tests` in `zbobr-repo-backend-github/src/github.rs`:

- Start a `wiremock::MockServer`
- Register mock: `GET /repos/org/repo` → 200 `{"full_name":"org/repo","fork":true}`
- Register mock: `POST /repos/org/repo/merge-upstream` → 422 `{"message":"Merge conflict",...}`
- Build octocrab with `base_uri(mock_server.uri())` and construct backend directly
- Call `backend.maybe_sync_fork(&repo, "main").await`
- Assert `Err(_)`

This validates the error-propagation fix (the bug from the second review round): a failed merge-upstream must not silently return `Ok(())`.
Add a `#[tokio::test]` in `mod tests` in `zbobr-repo-backend-github/src/github.rs`:

- Start a `wiremock::MockServer`
- Register mock: `GET /repos/org/repo` → 200 `{"full_name":"org/repo","fork":true}`
- Register mock: `POST /repos/org/repo/merge-upstream` → 200 `{"merge_type":"fast-forward"}`
- Build octocrab with `base_uri(mock_server.uri())` and construct backend directly
- Call `backend.maybe_sync_fork(&repo, "main").await`
- Assert `Ok(())`
- Assert wiremock received exactly 1 call to `POST /repos/org/repo/merge-upstream`

Validates the happy path: fork detection works, the correct API endpoint is called, and the response is accepted.
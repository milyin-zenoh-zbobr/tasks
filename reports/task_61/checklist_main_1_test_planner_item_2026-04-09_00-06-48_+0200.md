Add a `#[tokio::test]` in `mod tests` in `zbobr-repo-backend-github/src/github.rs`:

- Start a `wiremock::MockServer`
- Register a mock: `GET /repos/org/repo` → 200 `{"full_name":"org/repo","fork":false}`
- Build octocrab with `base_uri(mock_server.uri())` and `personal_token("test")`
- Construct `ZbobrRepoBackendGithub { backend_config, octocrab }` directly (private fields accessible from `mod tests`)
- Call `backend.maybe_sync_fork(&repo, "main").await`
- Assert `Ok(())`
- Assert wiremock received 0 calls to `POST /repos/org/repo/merge-upstream`

Validates that the "is it a fork?" gate prevents unnecessary merge-upstream calls for non-fork repos.
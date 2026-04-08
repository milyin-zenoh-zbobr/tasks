Add a `#[tokio::test]` in `mod tests` in `zbobr-repo-backend-github/src/github.rs`:

- Construct `ZbobrRepoBackendGithubConfig` with `auto_sync_fork: false`
- Build the backend via `ZbobrRepoBackendGithub::from_config(config).unwrap()`
- Construct a `GitHubRepo { full_name: "org/repo".to_string() }`
- Call `backend.maybe_sync_fork(&repo, "main").await`
- Assert `Ok(())`

No mock server needed — the method returns early before any HTTP call is made. This also guards against regressions that accidentally make API calls when the feature is disabled.
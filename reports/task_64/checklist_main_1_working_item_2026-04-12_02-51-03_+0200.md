Add `sync_fork_if_needed(&self, repo: &GitHubRepo)` method that:
1. Calls GET /repos/{full_name} via retry_github to get fork metadata
2. If fork == true, calls POST /repos/{owner}/{repo}/merge-upstream with {"branch": self.backend_config.branch}
3. Handles non-fatal errors: 409 (conflict), 422 (unprocessable), 403 (no push permissions) → tracing::warn! and continue
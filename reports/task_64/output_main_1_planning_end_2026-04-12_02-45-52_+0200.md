The plan is ready for review. Here's a summary:

**What changes**: Only `zbobr-repo-backend-github/src/github.rs`

1. **Extend `RepoResponse`** — add `fork: bool` to capture GitHub's fork flag
2. **New method `sync_fork_if_needed`** — uses the existing `retry_github` + `octocrab.get` pattern to check if repo is a fork, then calls `POST /repos/{owner}/{repo}/merge-upstream` with the configured base branch. Non-fatal errors (conflict, 403, 422) are logged as warnings and do not block the pipeline.
3. **Call `sync_fork_if_needed` in `ensure_bare_clone_github`** just before the existing `git fetch origin` — so the fetch picks up the freshly synced fork branch without any extra fetch step.
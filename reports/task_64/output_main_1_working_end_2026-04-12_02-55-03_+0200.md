Implementation complete. Here's a summary of what was done:

**Changes in `zbobr-repo-backend-github/src/github.rs`:**

1. **`ParentRepo` + `RepoResponse` extension** — added `fork: bool` and `parent: Option<ParentRepo>` fields so the existing `GET /repos/{owner}/{repo}` response captures fork metadata.

2. **`sync_fork_if_needed` method** — calls GitHub's `POST /repos/{owner}/{repo}/merge-upstream` API when the repo is a fork. HTTP 403/409/422 responses are non-fatal (warn + continue); other errors propagate. Non-fork repos return immediately without any API call.

3. **Hook into `ensure_bare_clone_github`** — inserted `self.sync_fork_if_needed(repo).await?` just before the existing `fetch origin`, so the fetch always picks up the freshly synced upstream content.
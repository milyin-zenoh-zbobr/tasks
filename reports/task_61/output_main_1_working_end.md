Implementation complete. Both checklist items are done:

1. **`auto_sync_fork: bool` config field** — added to `ZbobrRepoBackendGithubConfig` with `#[arg(long)]` and default `true`
2. **`maybe_sync_fork` method** — calls GitHub's merge-upstream API when the repo is a fork, placed in `impl ZbobrRepoBackendGithub` and invoked in `ensure_bare_clone_github` before `git fetch origin`
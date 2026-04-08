# Plan: Auto-sync fork (approved)

## Design decisions

- `auto_sync_fork: bool` defaults to `true` so existing users get the feature without config changes
- GitHub merge-upstream API (`POST /repos/{owner}/{repo}/merge-upstream`) is used — atomic, server-side, no local git operations needed
- Placement in `ensure_bare_clone_github` covers all fetch paths automatically
- Analog followed: `overwrite_author` bool in `ZbobrDispatcherConfig` for config field pattern; existing `retry_github` pattern in `github.rs` for API call

## Checklist

1. Add `auto_sync_fork: bool` to `ZbobrRepoBackendGithubConfig` in `zbobr-repo-backend-github/src/config.rs`
2. Add `maybe_sync_fork` method + call it before `git fetch origin` in `ensure_bare_clone_github` in `zbobr-repo-backend-github/src/github.rs`
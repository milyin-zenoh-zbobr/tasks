In `zbobr-repo-backend-github/src/config.rs`, add a new boolean field `auto_sync_fork` to the `ZbobrRepoBackendGithubConfig` struct.

- Default value: `true`
- Expose as a CLI argument with `#[arg(long)]`
- Follow the same pattern as `overwrite_author: bool` in `ZbobrDispatcherConfig` (in `zbobr-api/src/config/mod.rs`) — a plain bool field with `#[arg(long)]`, no additional attributes needed

Why: this flag controls whether the fork is automatically synced with upstream before each fetch. Defaulting to `true` means existing users get the behavior without config changes.
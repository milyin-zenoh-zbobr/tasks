# Fork Detection and Sync Feature - Codebase Exploration Report

## Overview
This is a Rust-based CI/CD automation system (zbobr) that manages tasks and updates code repositories via pull requests. The feature requirement is to "sync the destination repo before using it if it's a fork" - meaning if the configured destination repository is a fork of another repository, fetch the latest changes from the upstream before proceeding.

## Project Structure

### Key Modules
- **zbobr-repo-backend-github**: Handles all GitHub repository operations (cloning, worktrees, git operations)
- **zbobr-api**: Defines the WorktreeBackend trait that all repo backends implement
- **zbobr-dispatcher**: Main orchestrator that uses the backends
- **zbobr-utility**: Provides git command wrappers (git, git_env, git_output, git_check, etc.)

### Workspace Members
Located in `/data/home/skynet/tasks/base/workspaces/zbobr/task-64/zbobr/Cargo.toml`:
- zbobr-dispatcher (main orchestrator)
- zbobr-repo-backend-github (GitHub backend)
- zbobr-repo-backend-fs (filesystem backend)
- zbobr-task-backend-github (issue/PR backend)
- zbobr-task-backend-fs
- zbobr-executor-* (Claude, Copilot, MCP Tester)
- zbobr-api (trait definitions)
- zbobr-utility (git helpers)

## Current Repository Handling Flow

### 1. Configuration
**File**: `/data/home/skynet/tasks/base/workspaces/zbobr/task-64/zbobr/zbobr-repo-backend-github/src/config.rs`

```rust
pub struct ZbobrRepoBackendGithubConfig {
    pub repository: String,        // "owner/repo" format
    pub branch: String,            // base branch (e.g., "main")
    pub github_token: Secret,      // GitHub token
    pub repos_dir: PathBuf,        // directory for bare clones
}
```

### 2. Backend Initialization
**File**: `/data/home/skynet/tasks/base/workspaces/zbobr/task-64/zbobr/zbobr/src/commands.rs:226`

```rust
let repo_backend = ZbobrRepoBackendGithub::new(repo_config).await?;
```

This calls `validate_connectivity()` which verifies the repository exists on GitHub.

### 3. Bare Clone Creation
**File**: `/data/home/skynet/tasks/base/workspaces/zbobr/task-64/zbobr/zbobr-repo-backend-github/src/github.rs:299-344`

Function: `ensure_bare_clone_github()`

Current flow:
1. Creates directory at `repos_dir/{owner}__{repo}.git`
2. Clones the repository with `git clone --bare`
3. Configures fetch refspec: `+refs/heads/*:refs/remotes/origin/*`
4. Fetches from origin

**Critical Section for Fork Sync**: After line 341 `git_env(&bare_dir, &["fetch", "origin"], &env).await?;`

### 4. Worktree Operations
**File**: `/data/home/skynet/tasks/base/workspaces/zbobr/task-64/zbobr/zbobr-repo-backend-github/src/github.rs:347-448`

Function: `ensure_worktree_github()` 

Creates/reuses git worktrees for work branches.

### 5. Update Workflow
**File**: `/data/home/skynet/tasks/base/workspaces/zbobr/task-64/zbobr/zbobr-repo-backend-github/src/github.rs:689-809`

Function: `update_worktree()` - 10-phase workflow:
1. Setup (parse repo, ensure bare clone)
2. Validate base branch sync
3. Fetch remote work branch
4. Create worktree
5. Push if new branch
6. Abort in-progress merge
7. Stash uncommitted changes
8. Merge remote work → local work
9. Merge base → local work
10. Push result back

## GitHub API Integration

**Dependency**: octocrab (v0.49.5)

**File**: `/data/home/skynet/tasks/base/workspaces/zbobr/task-64/zbobr/zbobr-repo-backend-github/src/github.rs:192-210`

```rust
pub struct ZbobrRepoBackendGithub {
    backend_config: ZbobrRepoBackendGithubConfig,
    octocrab: octocrab::Octocrab,
}

// Initialization
let octocrab = octocrab::Octocrab::builder()
    .personal_token(token)
    .build()?;
```

### Current API Usage

1. **Repository existence check** (line 885):
```rust
self.octocrab
    .get::<RepoResponse, _, _>(format!("/repos/{repo_path}"), None::<&()>)
```

2. **Find existing PRs** (line 610):
```rust
self.octocrab
    .get(&endpoint, Some(&params))
    .await
```

3. **Create/Update PRs** (line 857):
```rust
self.octocrab.post(&endpoint, Some(&pr_payload)).await;
self.octocrab.patch::<serde_json::Value, _, _>(&endpoint, Some(&patch_payload)).await;
```

### Error Handling Pattern

**File**: Lines 19-64

- `octocrab_to_anyhow()`: Converts octocrab errors to anyhow::Error
- `is_transient_octocrab_error()`: Detects transient (retryable) errors
- `retry_github()`: Retries operations up to 3 times on transient errors

## Fork Detection Points

### Where to Add Fork Detection

**Primary Location**: `ensure_bare_clone_github()` in `/data/home/skynet/tasks/base/workspaces/zbobr/task-64/zbobr/zbobr-repo-backend-github/src/github.rs:299-344`

After the repository is cloned and confirmed to exist, the code should:

1. **Fetch repo metadata** via octocrab to detect if it's a fork
2. **If it's a fork**: Configure upstream remote and fetch
3. **Continue with normal operations**

### Secondary Location

**Before worktree creation**: `update_worktree()` calls `ensure_bare_clone_github()` at line 711, which is where the sync would first happen.

## Git Operations Available

**File**: `/data/home/skynet/tasks/base/workspaces/zbobr/task-64/zbobr/zbobr-utility/src/lib.rs:159-214`

Available utilities:
- `git_env()`: Run git with environment variables (used for token auth)
- `git()`: Run git without extra environment
- `git_output()`: Run git and capture stdout
- `git_check()`: Run git and return boolean success
- `git_check_env()`: Run git with env vars and return boolean

### Example Git Pattern from Code

The codebase already handles similar multi-step operations. Example from `sync_local_base_ref()` (lines 452-488):
```rust
let remote_sha = git_output(bare_dir, &["rev-parse", &remote_ref]).await;
// ... parse and update
git(bare_dir, &["update-ref", &local_ref, remote_sha.trim()]).await?;
```

## Required Implementation Steps

### 1. Fetch Fork Metadata
Extend `RepoResponse` struct (line 84) to include:
```rust
struct RepoResponse {
    full_name: String,
    fork: bool,
    parent: Option<ParentRepo>,  // Contains upstream repo info
}
```

### 2. Detect Fork in ensure_bare_clone_github()
After line 324 (after clone succeeds), add:
- Call GitHub API to get repo metadata
- Check if `fork == true`
- If fork, configure upstream remote

### 3. Sync Upstream
If fork detected, execute:
```bash
git remote add upstream https://github.com/{parent_owner}/{parent_repo}.git
git fetch upstream {base_branch}
# Optionally: git rebase upstream/{base_branch}
```

### 4. Integration Point
The sync should happen **inside** `ensure_bare_clone_github()` before returning the `bare_dir`, so that when `sync_local_base_ref()` is called in Phase 2 of `update_worktree()`, the local ref is already synchronized with upstream.

## Similar Patterns in Codebase

### Remote Configuration Pattern
**Lines 330-338**: Configuring fetch refspec
```rust
git(
    &bare_dir,
    &[
        "config",
        "remote.origin.fetch",
        "+refs/heads/*:refs/remotes/origin/*",
    ],
)
.await?;
```

### Fetch Pattern
**Line 341**: Fetching origin
```rust
git_env(&bare_dir, &["fetch", "origin"], &env).await?;
```

This exact pattern can be reused for upstream:
```rust
git_env(&bare_dir, &["fetch", "upstream", base_branch], &env).await?;
```

### Error Handling Pattern
**Lines 42-64**: Retry wrapper for API calls
```rust
retry_github("operation_name", || async {
    self.octocrab.get(endpoint, params)
}).await
```

## Dependencies Required

**Already present in Cargo.toml**:
- octocrab (v0.49.5) - for GitHub API
- tokio - for async operations
- anyhow - for error handling
- tracing - for logging

No additional dependencies needed.

## Testing Considerations

**Integration tests**: Located in `/data/home/skynet/tasks/base/workspaces/zbobr/task-64/zbobr/zbobr-dispatcher/tests/integration_github_github.rs`

Tests require credentials in `zbobr_github_test.toml` with:
- Task repository
- Fork repository (to test fork detection and sync)
- Tokens with appropriate permissions

## Key Files Summary

| File | Purpose | Key Functions |
|------|---------|----------------|
| `zbobr-repo-backend-github/src/github.rs` | Main backend logic | `ensure_bare_clone_github()`, `update_worktree()`, `fetch_refs()` |
| `zbobr-repo-backend-github/src/config.rs` | Configuration | `ZbobrRepoBackendGithubConfig`, validation |
| `zbobr-api/src/backend.rs` | Backend trait | `WorktreeBackend` trait definition |
| `zbobr-utility/src/lib.rs` | Git helpers | `git()`, `git_env()`, `git_output()`, `git_check()` |
| `zbobr/src/commands.rs` | Entry point | Backend initialization at line 226 |

## Codespace Patterns

The codebase already demonstrates patterns for:
1. **Octocrab API calls with retry logic** (lines 42-64, 882-889)
2. **Git operations with environment variable auth** (lines 224-240)
3. **Remote configuration** (lines 330-338)
4. **Fetching operations** (line 341, 816)
5. **Error conversion and logging** (lines 19-31)
6. **Async/await patterns** (throughout)

All these patterns can be directly applied to implement fork detection and upstream sync.

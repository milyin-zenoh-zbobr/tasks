## CRITICAL CODE PATH ANALYSIS: ZBOBR CODEBASE

### 1. `rewrite_authors_on_worktree` Function
**File:** `/data/home/skynet/tasks/base/workspaces/zbobr/task-70/zbobr/zbobr-utility/src/lib.rs`
**Lines:** 321-372

**Purpose:** Rewrites commit authors on a worktree branch using `git filter-branch`.

**What it does:**
- Takes all commits between `dest_branch` (typically the base branch) and `HEAD`
- Rewrites both author AND committer for all those commits to match configured git_user_name and git_user_email
- Uses `git filter-branch` instead of rebase to avoid merge conflicts during replay
- Operates in-place (modifies the worktree)

**Git commands used:**
1. `git rev-parse --show-toplevel` - Get the git repository root
2. Local git config set via `configure_git_user()` 
3. `git filter-branch -f --env-filter 'export GIT_AUTHOR_NAME=...; export GIT_AUTHOR_EMAIL=...; export GIT_COMMITTER_NAME=...; export GIT_COMMITTER_EMAIL=...;' '{dest_branch}'..HEAD`

**Key behavior:** This command REWRITES commit SHAs because it changes commit metadata (author/committer). This is the core challenge for "show commits in context" - pre-stored baseline SHAs become invalid after this runs.

**Code snippet:**
```rust
pub async fn rewrite_authors_on_worktree(
    work_dir: &Path,
    dest_branch: &str,
    git_user_name: &str,
    git_user_email: &str,
) -> Result<()> {
    // Get absolute path to the git repository
    let git_root = git_output(work_dir, &["rev-parse", "--show-toplevel"]).await?;
    let git_root_path = PathBuf::from(&git_root);

    // Configure git user locally
    configure_git_user(&git_root_path, git_user_name, git_user_email).await?;

    // Use git filter-branch to rewrite author/committer in-place.
    let filter_cmd = format!(
        "git filter-branch -f --env-filter '\
            export GIT_AUTHOR_NAME=\"{name}\";\
            export GIT_AUTHOR_EMAIL=\"{email}\";\
            export GIT_COMMITTER_NAME=\"{name}\";\
            export GIT_COMMITTER_EMAIL=\"{email}\";\
        ' '{dest}'..HEAD",
        name = git_user_name,
        email = git_user_email,
        dest = dest_branch,
    );
    // ... execute filter_cmd via shell
}
```

---

### 2. `perform_stash_and_push` Function
**File:** `/data/home/skynet/tasks/base/workspaces/zbobr/task-70/zbobr/zbobr-dispatcher/src/cli.rs`
**Lines:** 2115-2189 (full function)

**Purpose:** Stash uncommitted changes, optionally rewrite authors, and push changes back to remote.

**When it's called:**
- In `finalize_stage_session()` at 3 points:
  1. Line 2007-2012: If execution was interrupted
  2. Line 2019-2023: If there was an execution error
  3. Line 2043-2045: On normal completion (success path)

**How it calls `rewrite_authors_on_worktree`:**
```rust
if config.overwrite_author && is_uptodate && is_git_repo {
    let base_branch = self.repo_backend().branch().to_string();
    zbobr_utility::rewrite_authors_on_worktree(
        work_dir,
        &base_branch,
        &config.git_user_name,
        &config.git_user_email,
    )
    .await?;
    // Push rewritten commits
    let is_uptodate = self.update_worktree(&identity).await?;
    if !is_uptodate {
        anyhow::bail!(
            "Merge conflict while pushing rewritten commits for task #{task_id}"
        );
    }
}
```

**Full function flow:**
1. Check if work_dir is a git repository
2. If yes, check for uncommitted changes via `git status --porcelain`
3. If changes exist, stash with message: `"Stashed by {role} agent for task #{task_id}"`
4. Get task identity and check if it exists
5. Call `update_worktree(&identity)` to sync work branch with remote
6. Check `config.overwrite_author` flag - if true AND is_uptodate AND is_git_repo:
   - Call `rewrite_authors_on_worktree()` to rewrite commit authors
   - Call `update_worktree(&identity)` again to push the rewritten commits
   - If this results in merge conflicts, bail with error

**Key insight:** The rewrite happens AFTER the stage completes and AFTER pushing to remote, meaning the baseline SHAs from the stage start are now invalid.

---

### 3. `finalize_stage_session` Function
**File:** `/data/home/skynet/tasks/base/workspaces/zbobr/task-70/zbobr/zbobr-dispatcher/src/cli.rs`
**Lines:** 1994-2113 (full function, 120 lines)

**Full code:**
```rust
async fn finalize_stage_session(
    self: &Arc<Self>,
    task_id: u64,
    pipeline: &Pipeline,
    stage: &Stage,
    work_dir: &Path,
    outcome: SessionOutcome,
    last_mapped_tool: Option<McpTool>,
) -> anyhow::Result<Option<anyhow::Error>> {
    let task_session = self.task_session(task_id);
    let pending_state = State::pending(pipeline.clone());

    // INTERRUPTION PATH: Check if execution was interrupted
    if outcome.execution_interrupted {
        if let Err(e) = self
            .perform_stash_and_push(task_id, work_dir, stage.as_str(), pipeline)
            .await
        {
            tracing::warn!("Stash/push failed during interruption for task #{task_id}: {e}");
        }
        task_session.set_state(pending_state.clone()).await?;
        tracing::info!("Session interrupted for task #{task_id}, moved to {pending_state:?}");
        return Ok(None);
    }

    // ERROR PATH: Check if there was an execution error
    if let Some(e) = outcome.execution_error.as_ref() {
        if let Err(e) = self
            .perform_stash_and_push(task_id, work_dir, stage.as_str(), pipeline)
            .await
        {
            tracing::warn!("Stash/push failed during error handling for task #{task_id}: {e}");
        }
        let error_msg = format!("Execution failed: {e}");
        let status = format_error_status(self.config().fixed_offset(), &error_msg);
        let stage = stage.to_string();
        if let Err(pause_err) = task_session
            .set_pause_with_status_and_signal(status, Signal::go(stage.as_str()))
            .await
        {
            tracing::error!("Failed to set pause for task #{task_id}: {pause_err}");
        }
        task_session.set_state(pending_state.clone()).await?;
        tracing::info!(
            "Session failed for task #{task_id}, moved to {pending_state:?} with pause"
        );
        return Ok(outcome.execution_error);
    }

    // NORMAL COMPLETION PATH: Success
    tracing::info!("Session complete for task #{task_id}");

    if let Err(e) = self
        .perform_stash_and_push(task_id, work_dir, stage.as_str(), pipeline)
        .await
    {
        tracing::error!("Stash/push failed for task #{task_id}: {e}");
        let msg = format!("Stash/push failed: {e}");
        let status = format_error_status(self.config().fixed_offset(), &msg);
        let stage = stage.to_string();
        if let Err(pause_err) = task_session
            .set_pause_with_status_and_signal(status, Signal::go(stage.as_str()))
            .await
        {
            tracing::error!(
                "Failed to pause task #{task_id} after stash/push failure: {pause_err}"
            );
        }
        task_session.set_state(pending_state.clone()).await?;
        return Ok(None);
    }

    // SIGNAL COMPUTATION: Compute post-stage signal using sequential pipeline model
    let current_task = self
        .task_backend()
        .get_task(task_id)
        .await?
        .snapshot(false)
        .await?;
    // Track whether a pause was triggered this tick so we can skip the state reset below.
    // Keeping state as Running lets apply_pause_to_state derive calling_stage from
    // state.stage() (the stage that was actually running) rather than from the
    // pre-computed signal target.
    let pause_pending = current_task.go_pause;

    // Only compute signal if no pause and no signal already set
    if !current_task.go_pause && current_task.signal.is_none() {
        let current_stage = stage.clone();
        let stage_def = self.workflow().stage(pipeline, &current_stage);
        let seq_signal = self.workflow().sequential_signal(
            pipeline,
            &current_stage,
            stage_def,
            last_mapped_tool,
        );
        match seq_signal {
            SequentialSignal::ReturnFailure => {
                task_session.set_signal(Some(Signal::ReturnFailure)).await?;
            }
            SequentialSignal::Advance(next) => {
                task_session.set_signal(Some(Signal::go(next))).await?;
            }
            SequentialSignal::Return => {
                task_session.set_signal(Some(Signal::Return)).await?;
            }
        }
    }
    // If pause was set by MCP tool (e.g. stop_with_error) but no signal, set
    // signal to re-run the current stage on resume.
    if current_task.go_pause && current_task.signal.is_none() {
        task_session
            .set_signal(Some(Signal::go(stage.as_str())))
            .await?;
    }
    // Only reset state to Pending when no pause was triggered. When paused, keep
    // state as Running so apply_pause_to_state can read calling_stage from state.stage().
    if !pause_pending {
        task_session.set_state(pending_state).await?;
    }

    Ok(None)
}
```

**Key behaviors:**
- **3 code paths:** Interruption, Error, Success - each calls `perform_stash_and_push()`
- **Signal computation:** After successful stash/push, computes next signal based on pipeline sequencing
- **Pause handling:** If pause was triggered by MCP tool, keeps state as Running and sets signal to re-run current stage
- **State transitions:** Moves task to Pending state (unless paused)

---

### 4. Stage Iteration Loop - Main Execution Loop
**File:** `/data/home/skynet/tasks/base/workspaces/zbobr/task-70/zbobr/zbobr-dispatcher/src/cli.rs`
**Lines:** 540-700 (representative section)

**Loop structure:**
```rust
// Provider retry loop (line 526-699)
let mut cycle_excluded_providers: HashSet<String> = HashSet::new();
loop {
    // 1. SELECT PROVIDER
    let (resolved_provider, model) = self
        .zbobr
        .select_provider_excluding(&tool, &cycle_excluded_providers)?;
    
    // 2. PUSH STAGE CONTEXT
    {
        // Add new StageContext to task.context.stages (lines 532-561)
        let timestamp = chrono::Utc::now().with_timezone(&self.zbobr.config().fixed_offset());
        let role_session = self.zbobr.role_session(self.task_id);
        role_session
            .modify_task(move |mut task| {
                task.context.stages.push(StageContext {
                    info: StageInfo {
                        instance,
                        pipeline: pipeline_name,
                        stage: stage_name,
                        tool: tool_val,
                        model: model_val,
                        prompt_link: prompt_link_val,
                        output_link: None,
                        timestamp,
                    },
                    records: Vec::new(),
                });
                task
            })
            .await?;
    }

    // 3. START MCP SERVER
    let tool_tracker = Arc::new(std::sync::Mutex::new(None::<McpTool>));
    let (assigned_port, server_handle) = self
        .zbobr
        .start_mcp_server(
            role.clone(),
            self.task_id,
            resolved_provider.executor.clone(),
            model.clone(),
            self.stage.clone(),
            allowed_tools.clone(),
            Arc::clone(&tool_tracker),
            self.pipeline.clone(),
        )
        .await?;

    // 4. EXECUTE TOOL (lines 598-611)
    let outcome = execute_tool(
        executor,
        &copilot_token_owned,
        &agent_token_owned,
        self.task_id,
        role,
        model.as_str(),
        assigned_port,
        &prompt_text,
        &work_dir,
        &mcp_url,
        plan_mode,
    )
    .await;

    // 5. STORE OUTPUT (lines 613-644)
    if let Some(ref output) = outcome.execution_output {
        let role_session = self.zbobr.role_session(self.task_id);
        let base_name = format!("output_{}_{}_end", self.pipeline, self.stage);
        match role_session.store_report(&base_name, output).await {
            Ok(output_link) => {
                // Update StageContext with output_link
            }
            Err(e) => { /* warn */ }
        }
    }

    // 6. CHECK FOR FAILURE - RETRY LOOP
    if outcome.execution_failed {
        cycle_excluded_providers.insert(resolved_provider.provider.as_str().to_string());
        let attempts_remaining = self
            .zbobr
            .available_provider_model_count_excluding(&tool, &cycle_excluded_providers)?;
        server_handle.abort();
        if attempts_remaining > 0 {
            continue;  // RETRY PATH
        }
        // Fall through if no more attempts
    } else {
        self.zbobr
            .record_provider_success(resolved_provider.provider.as_str());
    }

    // 7. FINALIZE STAGE SESSION
    if let Some(e) = self
        .zbobr
        .finalize_stage_session(
            self.task_id,
            self.pipeline,
            self.stage,
            &work_dir,
            outcome,
            last_mapped_tool,
        )
        .await?
    {
        server_handle.abort();
        return Err(e);
    }

    server_handle.abort();
    return Ok(());  // EXIT LOOP - STAGE COMPLETE
}
```

**Key observations:**
- **StageContext is pushed at line 545** with empty records
- **Provider retry loop:** If execution fails, retries with next provider (continues the loop)
- **finalize_stage_session is called at line 683** which handles stash/push and author rewriting
- **Output link stored** after execution completes
- **Exit points:** Only exits on successful finalization or error

---

### 5. `commit_baseline` / `capture_git_head` Functions
**Status:** NOT FOUND in existing codebase

These functions do NOT currently exist. This is being introduced as part of the new feature.

---

### 6. `overwrite_author` Configuration
**File:** `/data/home/skynet/tasks/base/workspaces/zbobr/task-70/zbobr/zbobr-api/src/config/mod.rs`
**Lines:** 740-766

**Code:**
```rust
/// Rewrite commit authors after each stage completes to match configured git user.
pub overwrite_author: bool,

// ... in Default impl (line 766):
overwrite_author: false,
```

**What it does:**
- Boolean flag in ZbobrDispatcherConfig
- When true, triggers author rewriting in `perform_stash_and_push()` after each stage completes
- Default is false (disabled)
- Must be explicitly enabled by configuration

**Associated config fields:**
- `git_user_name: String` (line 737)
- `git_user_email: String` (line 738)

---

## CRITICAL FINDING: THE SHA REWRITING PROBLEM

The challenge for "show commits in context" feature:

1. **At stage START:** Baseline SHA is captured from HEAD of work branch
2. **Agent works:** Makes commits, pushes them
3. **At stage END:** `perform_stash_and_push()` is called (line 2043)
4. **Author rewriting:** If `overwrite_author=true`, `rewrite_authors_on_worktree()` runs (line 2175)
   - This uses `git filter-branch` which CHANGES commit SHAs
   - All commits between `base_branch..HEAD` are rewritten
5. **Push happens:** `update_worktree()` is called again (line 2183) to push rewritten commits
6. **Result:** Pre-stored baseline SHA is now INVALID because all commits after it have different SHAs

**The context record structure** (in `/data/home/skynet/tasks/base/workspaces/zbobr/task-70/zbobr/zbobr-api/src/task.rs`):
```rust
pub struct ContextRecord {
    pub id: u64,
    pub record_type: ContextRecordType,
    pub brief: String,
    pub report_link: Option<String>,
}

pub struct StageContext {
    pub info: StageInfo,
    pub records: Vec<ContextRecord>,  // Can store report links
}
```

**Solution approach:** Baseline SHA must be captured AFTER author rewriting (at end of stage), not at the beginning. Or it must be transformed when commits are rewritten.
# Zbobr Codebase Code Details

## 1. `zbobr-repo-backend-github/src/github.rs` - update_worktree Function

**Location**: Lines 762-882

### Function Signature and Overview
```rust
async fn update_worktree(
    &self,
    identity: &zbobr_api::task::TaskIdentity,
    workspace_path: &Path,
    git_user_name: &str,
    git_user_email: &str,
) -> anyhow::Result<bool>
```

This function synchronizes a worktree with both the remote work branch and the base branch. It performs a 10-phase operation:

**Phase 1: Setup** - Parse repo config and ensure bare clone exists
**Phase 2: Validate base branch sync** - Sync local base_ref with remote
**Phase 3: Fetch remote work branch** - Fetch work_branch from origin
**Phase 4: Create worktree** - Ensure worktree is initialized at workspace_path
**Phase 5: Push if new branch** - If remote doesn't exist, create placeholder commit and push
**Phase 6: Abort in-progress merge** - Check for and abort any MERGE_HEAD state
**Phase 7: Stash uncommitted changes** - Save local changes via git stash
**Phase 8: Merge remote work → local work** - If remote exists, merge origin/work_branch
**Phase 9: Merge base → local work** - Merge base_branch
**Phase 10: Push result back** - Push merged state (non-force)

Returns `Ok(true)` if all merges succeed, `Ok(false)` if merge conflict detected.

### Git Operations Performed

**Merge Helper Function** (lines 562-588):
```rust
async fn merge_ref_into_worktree(
    worktree_path: &Path,
    source_ref: &str,
) -> anyhow::Result<bool>
```
- Checks if source_ref is already ancestor of HEAD via `git merge-base --is-ancestor`
- If not ancestor: runs `git merge <source_ref> --no-edit`
- Returns success/failure status
- Does NOT force (--no-edit only suppresses message editor)

**Stash Helper Function** (lines 538-557):
```rust
async fn stash_worktree_changes(worktree_path: &Path) -> anyhow::Result<bool>
```
- Checks for changes via `git status --porcelain`
- If changes exist: `git stash push --include-untracked -m "auto-stash before merge"`

**Push Helper Function** (lines 592-604):
```rust
async fn push_worktree_to_origin(
    worktree_path: &Path,
    work_branch: &str,
    envs: &[(&str, &str)],
) -> anyhow::Result<()>
```
- Pushes via: `git push origin HEAD:<work_branch>` (no --force)
- Uses environment variables for authentication

### Key Implementation Details
- Lines 829-855: Merge-head detection handles both regular repos (.git directory) and worktree repos (.git file pointing to bare repo)
- Lines 810-823: Placeholder commit logic - creates empty commit only if no commits exist ahead
- Lines 860-868: Remote merge with conflict detection
- Lines 871-875: Base branch merge with conflict detection

---

## 2. `zbobr-dispatcher/src/cli.rs` - CLI Stage Runner Functions

### finalize_stage_session (lines 1994-2113)

```rust
async fn finalize_stage_session(
    self: &Arc<Self>,
    task_id: u64,
    pipeline: &Pipeline,
    stage: &Stage,
    work_dir: &Path,
    outcome: SessionOutcome,
    last_mapped_tool: Option<McpTool>,
) -> anyhow::Result<Option<anyhow::Error>>
```

Finalizes a stage session after agent execution. Handles three outcome scenarios:

**On Execution Interrupted** (lines 2006-2016):
- Calls `perform_stash_and_push`
- Sets task state back to Pending
- Returns early with None

**On Execution Error** (lines 2018-2039):
- Calls `perform_stash_and_push`
- Sets pause with error status and signal
- Sets state to Pending
- Returns the error

**On Success** (lines 2041-2112):
- Calls `perform_stash_and_push`
- Computes post-stage signal using sequential pipeline model
- Handles priority: agent's pre-set signal takes priority over computed signal
- Sets signal (ReturnFailure, Advance, or Return) based on workflow definition
- Only resets state to Pending if no pause was triggered (preserve Running state for paused tasks)

### perform_stash_and_push (lines 2115-2195)

```rust
async fn perform_stash_and_push(
    self: &Arc<Self>,
    task_id: u64,
    work_dir: &Path,
    role: &str,
    pipeline_name: &Pipeline,
) -> anyhow::Result<()>
```

Performs stashing and worktree synchronization:

**Stashing Logic** (lines 2127-2159):
- Checks if work_dir is a git repo via `git rev-parse --is-inside-work-tree`
- If repo exists, checks `git status --porcelain` for uncommitted changes
- If changes exist: `git stash push --include-untracked -m "Stashed by {role} agent for task #{task_id}"`
- Logs warnings but continues on stash failure

**Worktree Update** (lines 2161-2189):
- Gets task identity (work_branch, etc.)
- Calls `self.update_worktree(&identity)` for sync
- If merge conflict during sync (unless conflict handler mode): errors out
- If `config.overwrite_author && is_uptodate && is_git_repo`:
  - Calls `rewrite_authors_on_worktree` to rewrite commits
  - Updates worktree again and checks for conflicts
  - Pushes rewritten commits

### CliStageRunner::run Retry Loop (lines 523-700)

Located in the `run()` method of `CliStageRunner`:

**Provider Retry Loop** (lines 523-700):
```rust
let mut cycle_excluded_providers: HashSet<String> = HashSet::new();
loop {
    let (resolved_provider, model) = self
        .zbobr
        .select_provider_excluding(&tool, &cycle_excluded_providers)?;
    let plan_mode = resolved_provider.plan_mode;

    // Add StageContext entry (lines 532-561)
    // ... create and add stage context ...

    // Start MCP server and execute (lines 564-611)
    let outcome = execute_tool(...).await;

    // Store output link (lines 614-644)

    // Handle execution failure with retry (lines 649-671)
    if outcome.execution_failed {
        cycle_excluded_providers.insert(resolved_provider.provider.as_str().to_string());
        let attempts_remaining = self
            .zbobr
            .available_provider_model_count_excluding(&tool, &cycle_excluded_providers)?;
        let excluded = self
            .zbobr
            .record_provider_failure(resolved_provider.provider.as_str());
        server_handle.abort();
        if attempts_remaining > 0 {
            let exclusion_hint = if excluded {
                " (provider temporarily excluded)"
            } else {
                ""
            };
            tracing::warn!(
                "Provider '{}' failed for tool '{}' — retrying with next available provider{}",
                resolved_provider.provider.as_str(),
                tool,
                exclusion_hint,
            );
            continue;  // RETRY LOOP CONTINUES HERE
        }
        tracing::warn!(
            "Provider/model attempts exhausted for tool '{}' after a full cycle",
            tool
        );
    } else {
        self.zbobr
            .record_provider_success(resolved_provider.provider.as_str());
    }

    // Finalize and exit loop (lines 681-700)
    if let Some(e) = self
        .zbobr
        .finalize_stage_session(...)
        .await?
    {
        server_handle.abort();
        return Err(e);
    }
    server_handle.abort();
    return Ok(());
}
```

**Key Features**:
- Maintains `cycle_excluded_providers` set to track failed providers
- On failure: excludes provider, checks remaining attempts, retries if any
- Round-robin selection via `select_provider_excluding` with exclusion set
- Records provider success/failure for future load balancing
- Exits loop on success or exhausted attempts

---

## 3. `zbobr-utility/src/lib.rs` - Git Utility Functions

### rewrite_authors_on_worktree (lines 327-372)

```rust
pub async fn rewrite_authors_on_worktree(
    work_dir: &Path,
    dest_branch: &str,
    git_user_name: &str,
    git_user_email: &str,
) -> Result<()>
```

Rewrites commit authors using git filter-branch:

**Implementation**:
- Gets git root via `git rev-parse --show-toplevel`
- Configures git user locally via `configure_git_user`
- Constructs filter-branch command with env-filter:
  ```
  git filter-branch -f --env-filter '
    export GIT_AUTHOR_NAME="<name>";
    export GIT_AUTHOR_EMAIL="<email>";
    export GIT_COMMITTER_NAME="<name>";
    export GIT_COMMITTER_EMAIL="<email>";
  ' '<dest_branch>..HEAD'
  ```
- Runs via `sh -c` subprocess
- Sets both author AND committer to the same identity
- Rewrites all commits between dest_branch and HEAD (exclusive range using two dots)

**Advantages**: Does not replay changes like rebase, so cannot produce merge conflicts

### Supporting Utility Functions

**configure_git_user** (lines 224-244):
```rust
pub async fn configure_git_user(
    work_dir: &Path,
    git_user_name: &str,
    git_user_email: &str,
) -> Result<()>
```
- Sets `git config --local user.name`
- Sets `git config --local user.email`

**Git Command Wrappers**:
- `git(dir, args)` - Run git command, error on failure
- `git_output(dir, args)` - Run git and capture stdout
- `git_check(dir, args)` - Run git, return Ok(bool) on exit code 0/non-zero
- `git_env(dir, args, envs)` - Run git with extra environment variables

### Other Git Utility Functions

**cleanup_worktree_for_branch** (lines 268-319):
- Prunes worktree references
- Detects stale/non-functional worktrees
- Force-removes stale references
- Returns error if branch already checked out elsewhere

**create_placeholder_commit** (lines 250-254):
```rust
pub async fn create_placeholder_commit(work_dir: &Path, branch_name: &str) -> Result<()>
```
- Creates empty commit: `git commit --allow-empty -m "chore: add branch placeholder <branch>"`

**delete_placeholder_commit** (lines 377-379):
- No-op placeholder for backward compatibility

---

## 4. `zbobr-api/src/task.rs` - StageContext Struct

**Location**: Lines 177-186

```rust
#[derive(
    Debug, Clone, PartialEq, Eq, serde::Deserialize, serde::Serialize, schemars::JsonSchema,
)]
pub struct StageContext {
    /// Stage execution metadata.
    pub info: StageInfo,
    /// Context records produced during this stage.
    #[serde(default)]
    pub records: Vec<ContextRecord>,
}
```

### StageInfo (lines 152-174)

```rust
pub struct StageInfo {
    /// Zbobr instance name that produced this stage.
    pub instance: String,
    /// Pipeline that owns this stage.
    pub pipeline: Pipeline,
    /// Stage name within the pipeline.
    pub stage: Stage,
    /// Executor/provider used for this stage (e.g. "claude", "copilot", or a provider name).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool: Option<String>,
    /// Model string used by the executor.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<Model>,
    /// Link to the prompt used for this stage.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt_link: Option<String>,
    /// Link to the captured output of this stage.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_link: Option<String>,
    /// Timestamp when the stage was created.
    #[schemars(with = "String")]
    pub timestamp: chrono::DateTime<chrono::FixedOffset>,
}
```

### TaskContext (lines 188-230)

```rust
#[derive(
    Debug, Clone, PartialEq, Eq, Default, serde::Deserialize, serde::Serialize, schemars::JsonSchema,
)]
pub struct TaskContext {
    /// Ordered list of stage contexts.
    #[serde(default)]
    pub stages: Vec<StageContext>,
}
```

With methods:
- `next_id()` - Returns max existing record id + 1
- `find_record(id)` - Find record by id and its stage index
- `find_record_mut(id)` - Mutable version of find_record

---

## 5. `zbobr-api/src/context/mod.rs` - MdStage Struct

**Location**: Lines 363-480

### MdStage Struct Definition (lines 363-367)

```rust
struct MdStage {
    title: MdStageTitle,
    records: Vec<MdRecord>,
    for_prompt: bool,
}
```

### Display Implementation (lines 369-401)

```rust
impl fmt::Display for MdStage {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.for_prompt {
            writeln!(f, "- {}", self.title.stage)?;
        } else {
            writeln!(f, "- {}", self.title)?;
        }

        // Flatten output: all records on the same level
        // Reorder so first non-checkbox item is first in output
        let mut ordered = self.records.clone();
        if let Some(non_checkbox_idx) = ordered.iter().position(|r| {
            !matches!(
                r.record_type,
                MdRecordType::CheckboxUnchecked | MdRecordType::CheckboxChecked
            )
        }) && non_checkbox_idx != 0
        {
            let non_checkbox = ordered.remove(non_checkbox_idx);
            ordered.insert(0, non_checkbox);
        }

        for record in ordered {
            let indent = match record.record_type {
                MdRecordType::CheckboxUnchecked | MdRecordType::CheckboxChecked => "    ",
                _ => "  ",
            };
            writeln!(f, "{}{}", indent, record)?;
        }

        Ok(())
    }
}
```

### FromStr Implementation (lines 403-429)

```rust
impl FromStr for MdStage {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self> {
        let mut lines = s.lines();
        let first = lines.next().ok_or_else(|| anyhow::anyhow!("Empty stage"))?;
        let title: MdStageTitle = first.parse()?;
        let mut records = Vec::new();

        for line in lines {
            if line.trim().is_empty() {
                continue;
            }

            let trimmed = line.trim();

            if let Some(record) = MdRecord::try_parse(trimmed)? {
                records.push(record);
            }
        }
        Ok(MdStage {
            title,
            records,
            for_prompt: false,
        })
    }
}
```

### Serialization (lines 431-441)

```rust
impl serde::Serialize for MdStage {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.to_string())
    }
}

impl<'de> serde::Deserialize<'de> for MdStage {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let s = String::deserialize(deserializer)?;
        s.parse().map_err(serde::de::Error::custom)
    }
}
```

**Serialization Strategy**: Serializes to string representation via `Display`, deserializes by parsing string via `FromStr`.

### from_stage_context Method (lines 444-480)

```rust
fn from_stage_context(
    stage: &StageContext,
    for_prompt: bool,
    report_url: Option<&dyn Fn(&str) -> String>,
) -> Self {
    let mut title = MdStageTitle::from(&stage.info);

    // Transform prompt/output link URLs if needed
    for link in [&mut title.prompt_link, &mut title.output_link]
        .into_iter()
        .flatten()
    {
        if !link.starts_with("http://")
            && !link.starts_with("https://")
            && let Some(f) = report_url
        {
            *link = f(link);
        }
    }

    // Omit prompt and output links for agent prompts
    if for_prompt {
        title.prompt_link = None;
        title.output_link = None;
    }

    let records = stage
        .records
        .iter()
        .map(|r| MdRecord::from_context_record(r, for_prompt, report_url))
        .collect();

    MdStage {
        title,
        records,
        for_prompt,
    }
}
```

---

## 6. `zbobr/src/commands.rs` - overwrite_author Command Handler

**Location**: Lines 609-690+ (showing full function through completion)

```rust
async fn overwrite_author(
    zbobr: &Arc<ZbobrDispatcher>,
    id: u64,
    force: bool,
    dry_run: bool,
) -> anyhow::Result<()> {
    let task_backend = zbobr.task_backend();
    let task = task_backend.get_task(id).await?.snapshot(false).await?;
    let identity = task
        .identity()
        .ok_or_else(|| anyhow::anyhow!("Task #{} missing work_branch", id))?;

    let dest_repo = zbobr.repo_backend().repository();
    let dest_branch = zbobr.repo_backend().branch();

    if dry_run {
        println!(
            "Dry run: would rewrite commit authors in repo '{}' (PR: '{}')",
            dest_repo, task.title
        );
    } else if !force {
        println!(
            "This will rewrite commit authors in repo '{}' (PR: '{}'). Continue? (yes/no)",
            dest_repo, task.title
        );
        let mut input = String::new();
        std::io::stdin().read_line(&mut input)?;
        if !input.trim().eq_ignore_ascii_case("yes") {
            println!("Cancelled");
            return Ok(());
        }
    }

    let task_dir = TaskDir::new(zbobr.config().workspaces.as_path(), id);
    let repo_name = zbobr.repo_backend().repo_name();
    let repo_dir = task_dir.path().join(repo_name);

    if !repo_dir.exists() {
        return Err(anyhow::anyhow!(
            "Task repo not found at {}. Run 'zbobr task clone {}' first.",
            repo_dir.display(),
            id
        ));
    }

    // Fetch latest refs via the auth-aware backend so that filter-branch
    // range and dry-run log are accurate.
    zbobr.fetch_refs(&identity).await?;

    if !dry_run {
        let config = zbobr.config();
        zbobr_utility::rewrite_authors_on_worktree(
            &repo_dir,
            dest_branch,
            &config.git_user_name,
            &config.git_user_email,
        )
        .await?;
        // Sync and push rewritten commits
        match zbobr.update_worktree(&identity).await {
            Ok(true) => {}
            Ok(false) => {
                tracing::warn!("Merge conflict while pushing rewritten commits for task #{id}");
            }
            Err(e) => {
                tracing::warn!("Could not push rewritten commits for task #{id}: {e}");
            }
        }
        println!("Successfully rewrote commit authors and pushed");
    } else {
        if let Ok(log) = git_output(
            &repo_dir,
            &[
                "log",
                &format!("{}..HEAD", dest_branch),
                "--format=%H %an <%ae>",
            ],
        )
        .await
        {
            // Display dry-run output
        }
    }
}
```

**Key Behavior**:
- Line 615-619 not shown but called as entry point
- Gets task identity to verify work_branch exists
- User confirmation required (unless --force or --dry-run)
- Calls `rewrite_authors_on_worktree` to rewrite commits
- Calls `update_worktree` to sync and push
- Handles merge conflicts gracefully (logs warning)
- Supports dry-run via git log to show what would be rewritten

---

## 7. `zbobr/src/init.rs` - REVIEWER_PROMPT Constant

**Location**: Lines 904-945

```rust
const REVIEWER_PROMPT: &str = concat!(
    r#"# Reviewer Agent

Review the implementation changes and ensure they meet coding standards and task requirements.

"#,
    get_ctx_rec_guidance!(),
    r#"

## Access Model

    You have read-only access to the task plan and access to the repository for inspection:
    - The task description, work plan, worker's reports, and context are provided below in this prompt. The full history and checklist are available in the context section.
    - Your current working directory is already the repository with the work branch checked out — examine changes directly
    - Use `{mcp_stop_with_error}` only to report technical errors
    - You can send multiple success or failure reports to provide detailed feedback on different aspects.

## Workflow

1. Read the task description, work plan, worker's reports, and context provided below in this prompt. Note if the analog solution in the existing code is referenced in the plan.
2. **Inspect all changes made in this task**: Use `git diff origin/<destination_branch>...HEAD` (three dots) to see ALL changes introduced by this task relative to the base branch. Do NOT checkout the base branch (it may conflict with worktree setup). You can also use `git log origin/<destination_branch>..HEAD` to see all commits in this branch.
3. **Verify the analog choice and pattern consistency**: Check that the planner chose an appropriate analog for the new functionality. Then verify that the implementation consistently follows the same patterns, conventions, coding style, and architectural approaches as the analog. Flag any deviations — new code should look like it was written by the same author as the existing analogous code. If the analog was poorly chosen, note this as a review finding.
4. **Review code quality and correctness**: Examine the implementation for correctness, code style, design patterns, and adherence to the plan. **Do not run any tests yourself; testing is handled separately.**
5. Verify that all changes are related to the task and are necessary for the implementation. But accept the unrelated changes if they are formatting and linting changes or if they were introduced by the user according to the git history.
6. Additionally review each unchecked checklist item in the task context:
    - If you verify the item is correctly implemented or just became obsolete due to further changes, call `{mcp_check_checklist_item}` with the item's ID
    - If the item's implementation is missing and it's still relevant, leave it unchecked and report this in the review findings.
7. Prepare a detailed review report describing any issues found, suggested fixes, and overall assessment. Include your assessment of analog consistency.
8. Finish the review by calling one of:
    - `{mcp_report_success}` — the implementation is correct and **all checklist items are completed**.
    - `{mcp_report_intermediate}` — the implementation of completed items looks correct, but **some checklist items remain unchecked**.
    - `{mcp_report_failure}` — issues were found in the implementation that must be fixed.
   Pass the review report as a parameter.

## Review Guidelines

- **Check compile-time validation**: Verify whether code correctness can be enforced at compile time (e.g., through type system, constants, enums) rather than relying on runtime checks or string matching. Flag opportunities to strengthen compile-time guarantees.
- **Check robustness against inconsistent changes**: Verify that the code is resilient to partial updates — e.g., changing a constant or literal in one place and forgetting to update it elsewhere. Flag hardcoded string literals that could be derived from existing types or constants. But don't be overzealous — not every literal needs to be served as a constant, especially in examples, demonstrations, or tests.
- **Check type specificity**: Verify that all newly introduced fields, variables, parameters, and return types use the most specific type available for their purpose. Suspect all base types (numbers, strings, booleans) — search the codebase for existing custom types, newtypes, or domain-specific wrappers that should be used instead.
- **Check test value**: Flag tests that only verify static prompt/config content as low-value and brittle unless exact text/value is an explicit runtime or API contract.
- **Prefer behavior-oriented tests**: Favor findings and suggestions toward tests that validate observable behavior, transitions, integration boundaries, and failure paths."#,
);
```

**Key Features**:
- Uses `concat!` macro to combine string slices
- Includes `get_ctx_rec_guidance!()` macro (context record guidance)
- Contains placeholder tokens like `{mcp_stop_with_error}`, `{mcp_check_checklist_item}`, `{mcp_report_success}`, etc.
- Instructs reviewer to check analog consistency between implementation and codebase patterns
- Defines completion conditions: success (all items done), intermediate (some items remain), failure (issues found)
- Emphasizes compile-time validation, type specificity, and behavior-oriented testing

---

## Summary of Code Architecture

The zbobr system uses a multi-layer architecture:

1. **Backend Layer** (`*-backend-*`): Implements repository operations (GitHub, filesystem)
2. **Dispatcher Layer** (`zbobr-dispatcher`): Orchestrates task execution, stage running, MCP server management
3. **API Layer** (`zbobr-api`): Defines common types, task context, pipeline definitions
4. **Utility Layer** (`zbobr-utility`): Shared git and configuration utilities
5. **CLI Layer** (`zbobr`): Command-line interface with init prompts and command handlers

The `update_worktree` function is central to synchronization, performing merges (not force-push) to maintain history. The CLI stage runner uses a retry loop for provider selection. Author rewriting via filter-branch preserves commit DAG integrity while changing authorship metadata.

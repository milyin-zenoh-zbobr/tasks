Review result: **not ready to accept** due to one blocking issue.

## Overall assessment
- **Analog choice:** good. Using the existing plain config-bool pattern and the existing `retry_github` flow in `github.rs` is consistent with the approved plan.
- **Pattern consistency:** the new `maybe_sync_fork()` hook is placed at the right choke point (`ensure_bare_clone_github`) and the earlier silent-failure problem appears fixed correctly by propagating `merge-upstream` errors.
- **Blocking issue:** the new config field was added to `ZbobrRepoBackendGithubConfig` but not propagated to at least one existing struct literal outside the edited crate.

## Finding 1 — downstream `ZbobrRepoBackendGithubConfig` constructor is now incomplete
**Files:**
- `zbobr-repo-backend-github/src/config.rs:24-37`
- `zbobr-dispatcher/tests/mcp_integration/env.rs:258-263`

`ZbobrRepoBackendGithubConfig` now has a new required field:
- `auto_sync_fork: bool`

However, `zbobr-dispatcher/tests/mcp_integration/env.rs` still constructs the config with a full struct literal that only sets:
- `repository`
- `branch`
- `github_token`
- `repos_dir`

and does **not** set `auto_sync_fork` or use `..Default::default()`.

That means this task’s API change has not been fully wired through all affected call sites. At minimum, that integration-test path is now inconsistent with the updated type and will fail to compile whenever that test target is built.

Why this matters:
1. The task introduced a public config-surface change, so all explicit constructors of that config type need to be updated together.
2. This is exactly the kind of breakage that should be caught at compile time, and right now the branch leaves one compile-time consumer behind.
3. It weakens confidence that the feature is fully integrated across the workspace, even though the main crate changes themselves look correct.

**Suggested fix:**
- Update `zbobr-dispatcher/tests/mcp_integration/env.rs` to set `auto_sync_fork` explicitly (likely `true` to preserve the new default behavior), or switch that literal to use `..Default::default()` where appropriate.

## Analog consistency note
The planner’s analogs were appropriate, and the implementation follows them well in the repo backend itself. The remaining inconsistency is not stylistic but integration-related: the new config field was not applied everywhere the config type is manually constructed.

## Checklist status
- No unchecked checklist items were present in the provided context.
- Even so, the branch should not be accepted until the missing constructor update above is fixed.
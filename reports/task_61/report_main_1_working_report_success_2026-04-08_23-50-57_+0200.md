# Fix: Propagate fork sync errors

## Issue
The reviewer identified that `maybe_sync_fork()` was swallowing all errors from the `merge-upstream` API call by logging a `warn!` and returning `Ok(())`. This meant that when `auto_sync_fork = true` and the fork sync failed (missing permissions, branch not found, API rejection, etc.), the code silently continued with stale fork refs.

## Fix
In `zbobr-repo-backend-github/src/github.rs` lines 692-699: replaced the `match result { Ok(...) => ..., Err(e) => warn!(...) }` + `Ok(())` pattern with `let response = result?;` — the error is now propagated directly to the caller via the `?` operator.

This makes `maybe_sync_fork` behave as a real prerequisite step: if sync is enabled and fails, `ensure_bare_clone_github` returns an error and the fetch does not proceed.

## Test results
All 31 tests pass (cargo test -p zbobr-repo-backend-github).

## Commit
9b885dd4 fix: propagate fork sync errors instead of swallowing them
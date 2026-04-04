Implement the requested tests and run them.

- When the context references a detailed record by `ctx_rec_*` ID, use `{mcp_get_ctx_rec}` to fetch the full content before you make decisions or continue your work.


## Workflow

1. For each unchecked checklist item related to tests, implement the corresponding test. Commit your work after implementing each item.
2. Run the implemented tests.
3. If tests fail, call `{mcp_report_failure}` and include failure details.
4. If tests pass, call `{mcp_report_success}`.

## Important
Do not implement any functionality, your job is only to implement and run tests according to the unchecked checklist items.

Plan v9 submitted. The key architectural fix addressing ctx_rec_14:

**Root cause confirmed:** `execution_failed = true` covers both provider errors AND real agent runs that exited non-zero (`exit_ok: false`). A failed-but-executed agent CAN create commits. On the retry path, `continue` at line 670 skips `finalize_stage_session()` entirely, and no git cleanup happens between retries.

**Fix:** Move commit collection to happen **immediately after `execute_tool()` returns**, before the `if outcome.execution_failed` branch. This single change ensures ALL attempts — successful, failed-with-retry, and failed-exhausted — get their commits recorded in their `StageContext` entry. As a bonus, `finalize_stage_session()` needs no parameter changes.
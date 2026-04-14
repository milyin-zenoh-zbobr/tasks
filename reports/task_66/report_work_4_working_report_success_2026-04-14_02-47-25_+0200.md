# Fix: Unique ports per test in ConnectivityTest

## Issue
The review found that `ConnectivityTest` used a single shared port constant `LISTEN_PORT = 7460` across all 9 tests, making the suite order-dependent and prone to flakes when sockets aren't fully released between tests.

## Fix
Replaced the single shared constant with a helper function pair `listenerConfig(port: Int)` / `connectConfig(port: Int)` and assigned each test its own unique port (7465–7473).

| Test | Port |
|------|------|
| transports list is non-empty when connected | 7465 |
| links list is non-empty when connected | 7466 |
| links list filtered by transport | 7467 |
| transport events listener PUT/DELETE | 7468 |
| transport events listener with history | 7469 |
| link events listener PUT/DELETE | 7470 |
| link events listener with history and filter | 7471 |
| background transport events listener | 7472 |
| background link events listener | 7473 |

## Verification
All 9 ConnectivityTest tests pass: `SUCCESS: Executed 9 tests in 11.4s`

Commit: `76042c5a` - "fix: use unique ports per test in ConnectivityTest (7465-7473)"
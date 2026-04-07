The updated plan is ready for your review. Key changes from the previous version:

- **Both Transport and Link now wrap C owned structures equally** (per your feedback) — no more "pure Go struct" for Link
- Both types get accessor methods via `C.z_*_loan()`, plus Clone/Drop
- Callbacks clone from loaned→owned so Go holds independent copies
- Event listeners follow the established Subscriber pattern
- New files: `transport.go`, `link.go`, `connectivity.go`, C bridge additions, and an example
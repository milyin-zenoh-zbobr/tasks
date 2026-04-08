Add `wiremock = "0.6"` to `[workspace.dependencies]` in the root `Cargo.toml`, then add `wiremock = { workspace = true }` to `[dev-dependencies]` in `zbobr-repo-backend-github/Cargo.toml`. This is a prerequisite for the HTTP-mock-based tests (tests 2–4).

File: `Cargo.toml` (workspace) and `zbobr-repo-backend-github/Cargo.toml`
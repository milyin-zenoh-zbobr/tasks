Running a repository search to locate formatting and lint commands in CI and build files so the same checks can be run locally. Reporting intent: "Discovering linters". I'll search common linter/formatter keywords in .github/workflows and root build files.

● Search (grep)
  │ "markdownlint|mdl|markdownlint-cli|markdownlint-cli2|markdownlint-rules|MD0"
  │ (.github/workflows)
  └ 2 lines found

● Search (grep)
  │ "(spotless|ktlint|detekt|ktfmt|ktlint|ktfmt|ktlint|ktlint)"
  └ No matches found

● Search (grep)
  │ "(fmt|format|lint|black|prettier|eslint|gofmt|clippy|ktlint|detekt|markdownl
  │ int|mdl|shellcheck|spotless|ktfmt|ktlint|ktlint)" (.github/workflows)
  └ 5 lines found

● Search (grep)
  │ "prettier|eslint|stylelint|tslint" (.github/workflows)
  └ No matches found

● Read ci.yml
  │ .github/workflows/ci.yml
  └ 87 lines read

● Read settings.gradle.kts
  └ 46 lines read

● Read build.gradle.kts
  └ 62 lines read

● Read .markdownlint.yaml
  └ 7 lines read

● Read publish-jvm.yml
  │ .github/workflows/publish-jvm.yml
  └ 76 lines read

● Read publish-android.yml
  │ .github/workflows/publish-android.yml
  └ 75 lines read

Running markdownlint-cli2 via npx to check README.md using the project's .markdownlint.yaml config. This replicates CI's markdown_lint job.

● Run markdownlint-cli2 on README.md per CI config (shell)
  │ npx --yes markdownlint-cli2 "**/README.md" -c .markdownlint.yaml
  └ 6 lines...

● report_success (MCP: zbobr) · brief: "Formatting/lint checks passed: markdownlint", full_report: …
  └ Report stored

Summary: Found CI linter: markdownlint (checks **/README.md). Ran: npx --yes markdownlint-cli2 "**/README.md" -c .markdownlint.yaml — Summary: 0 errors. All formatting/lint checks passed.

--- stderr ---

Changes   +0 -0
Requests  0 Premium (1m 48s)
Tokens    ↑ 217.8k • ↓ 3.1k • 209.8k (cached) • 2.0k (reasoning)
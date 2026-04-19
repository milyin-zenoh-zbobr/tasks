Discovering CI and build config files to find formatting/lint commands. Running fast glob searches for workflows and common build files.

● Search (glob)
  │ "package.json"
  └ No matches found

● Search (glob)
  │ "pom.xml"
  └ No matches found

● Search (glob)
  │ "gradle/**"
  └ No matches found

● Search (glob)
  │ "gradle.properties"
  └ 2 files found

● Search (glob)
  │ "settings.gradle.kts"
  └ 2 files found

● Search (glob)
  │ "build.gradle.kts"
  └ 7 files found

● Search (glob)
  │ "ci/**"
  └ 1 file found

● Search (glob)
  │ ".github/workflows/**"
  └ 7 files found

● Search (glob)
  │ "Makefile"
  └ No matches found

● Search (glob)
  │ "pyproject.toml"
  └ No matches found

● Read ci.yml
  │ .github/workflows/ci.yml
  └ 87 lines read

● Read publish-jvm.yml
  │ .github/workflows/publish-jvm.yml
  └ 76 lines read

● Read publish-android.yml
  │ .github/workflows/publish-android.yml
  └ 75 lines read

● Read build.gradle.kts
  └ 62 lines read

● Read build.gradle.kts
  │ zenoh-kotlin/build.gradle.kts
  └ 191 lines read

● Read settings.gradle.kts
  └ 46 lines read

● Read gradle.properties
  └ 12 lines read

● Read build.gradle.kts
  │ zenoh-java/zenoh-jni-runtime/build.gradle.kts
  └ 252 lines read

● Search (grep)
  │ "detekt" in **/* (./)
  └ No matches found

● Search (grep)
  │ "gofmt" in **/* (./)
  └ No matches found

● Search (grep)
  │ "eslint" in **/* (./)
  └ No matches found

● Search (grep)
  │ "spotless" in **/* (./)
  └ No matches found

● Search (grep)
  │ "black" in **/* (./)
  └ 2 lines found

● Search (grep)
  │ "checkstyle" in **/* (./)
  └ No matches found

● Search (grep)
  │ "prettier" in **/* (./)
  └ No matches found

● Search (grep)
  │ "ktfmt" in **/* (./)
  └ No matches found

● Search (grep)
  │ "ktlint" in **/* (./)
  └ No matches found

● Search (glob)
  │ ".markdownlint.yaml"
  └ 2 files found

● Read .markdownlint.yaml
  └ 7 lines read

Running markdownlint-cli2 via npx to reproduce the CI markdown_lint job locally and report findings.

● Run markdownlint on README files (shell)
  │ npx --yes markdownlint-cli2 "**/README.md" --config .markdownlint.yaml
  │ --no-color || true
  └ 7 lines...

● report_failure (MCP: zbobr) · brief: "Formatting/lint checks failed: markdownlint found 1 error",…
  └ Report stored

Result: formatting/lint checks failed.

Summary: markdownlint (the CI markdown_lint job) reported 1 error:
- zenoh-java/README.md:165:35 — MD059/descriptive-link-text (Link text should be descriptive; context: "[here]")

Commands run:
- npx --yes markdownlint-cli2 "**/README.md" --config .markdownlint.yaml --no-color

Full output was captured in the failure report.

--- stderr ---

Changes   +0 -0
Requests  0 Premium (2m 17s)
Tokens    ↑ 370.8k • ↓ 3.5k • 323.3k (cached) • 2.1k (reasoning)
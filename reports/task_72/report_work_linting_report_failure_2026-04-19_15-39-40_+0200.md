Commands run:
1) npx --yes markdownlint-cli2 "**/README.md" --config .markdownlint.yaml --no-color

Output:
markdownlint-cli2 v0.22.0 (markdownlint v0.40.0)
Finding: **/README.md --no-color
Linting: 4 file(s)
Summary: 1 error(s)
zenoh-java/README.md:165:35 error MD059/descriptive-link-text Link text should be descriptive [Context: "[here]"]

Interpretation:
- CI defines only a markdown lint job for formatting checks. No Kotlin linters (ktlint/detekt/spotless) found in repo or CI.
- The markdownlint check fails due to MD059 in zenoh-java/README.md (non-descriptive link text '[here]').

Next steps (not performed here per instructions):
- Update zenoh-java/README.md to replace non-descriptive link text (e.g., use descriptive text instead of "here").
- Re-run the markdownlint command to verify the fix.

Full command output is above.
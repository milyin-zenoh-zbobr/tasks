Commands run:
1) cargo fmt --all -- --check
2) cargo clippy --all-targets --all-features -- -D warnings

Output (truncated to relevant part):

Diff in zbobr-macros/src/lib.rs:7:
 use heck::ToSnakeCase;
 use proc_macro::TokenStream;
 use proc_macro2::{Span, TokenStream as TokenStream2};
-use quote::{ToTokens, format_ident, quote};
+use quote::{format_ident, quote, ToTokens};
 use syn{
-    Attribute, Fields, GenericArgument, ItemStruct, Lit, LitStr, Meta, Token, Type, TypePath,
-    parse_macro_input, punctuated::Punctuated,
+    parse_macro_input, punctuated::Punctuated, Attribute, Fields, GenericArgument, ItemStruct, Lit,
+    LitStr, Meta, Token, Type, TypePath,
 };

Diff in zbobr/src/init.rs:1120:
-        let task_prompt = merging
-            .prompts
-            .as_ref()
-            .and_then(|map| map.get("task"));
+        let task_prompt = merging.prompts.as_ref().and_then(|map| map.get("task"));

Multiple diffs in zbobr-repo-backend-github/src/github.rs: formatting changes to ensure compact serde_json! macros are on single lines.

Diff in zbobr-task-backend-github/src/github.rs:94: chrono::Local::now() formatting wrapped across lines.

Diff in zbobr-task-backend-github/src/github.rs:1812: assert_eq! formatting updated to multi-line.

Exit code: 1 (cargo fmt reported differences). cargo clippy was not executed because the previous command failed.

Actionable items for developer:
- Run `cargo fmt --all` to apply formatting changes locally, then re-run the checks.
- After formatting passes, run `cargo clippy --all-targets --all-features -- -D warnings` to surface remaining lints.

Full raw output available in CI run; above includes the diffs reported by rustfmt.

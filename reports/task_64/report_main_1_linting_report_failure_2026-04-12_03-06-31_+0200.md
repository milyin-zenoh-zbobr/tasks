Discovery:
- No .github/workflows lint/format steps found.
- Inspected Cargo.toml (workspace) and clippy_output.txt.

Commands executed:
1) cargo fmt --all -- --check
Exit: 1
Output (snippet):
Diff in zbobr-macros/src/lib.rs:
 use heck::ToSnakeCase;
 use proc_macro::TokenStream;
 use proc_macro2::{Span, TokenStream as TokenStream2};
- use quote::{ToTokens, format_ident, quote};
+ use quote::{format_ident, quote, ToTokens};
 use syn::{
-    Attribute, Fields, GenericArgument, ItemStruct, Lit, LitStr, Meta, Token, Type, TypePath,
-    parse_macro_in

2) cargo clippy --workspace --all-targets --all-features -- -D warnings
Exit: 101
Output (snippet):
CLIPPY errors (examples):
- collapsible_if: zbobr-utility/src/toml_edit_util.rs:49: nested if can be collapsed (suggestion: combine with && let)
- derivable_impls: zbobr-utility/src/toml_option.rs:28: impl<T> Default for TomlOption<T> can be derived (suggested #[derive(Default)] and #[default] on Absent)

Full clippy output saved in repository at clippy_output.txt. Many crates produced warnings in previous runs (see clippy_output.txt lines referencing zbobr-api, zbobr-dispatcher, etc.).

Summary:
- cargo fmt --all -- --check failed (format diffs present).
- cargo clippy with -D warnings failed (clippy lints triggered errors).

Next steps (not performed here):
- Run `cargo fmt --all` to apply formatting.
- Address or allow the clippy suggestions (or run `cargo clippy --fix` per-package where safe).

Commands run and outputs are available in the CI run logs above. Please let me know if a different set of lint commands should be used (e.g., allow clippy warnings instead of -D warnings).
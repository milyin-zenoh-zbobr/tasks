Commands run:
- cargo fmt --all -- --check
- cargo clippy --all-targets --all-features -- -D warnings

Full output:
== cargo fmt ==
Diff in /data/home/skynet/tasks/base/workspaces/zbobr/task-61/zbobr/zbobr-macros/src/lib.rs:7:
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
 
 #[proc_macro_attribute]
Diff in /data/home/skynet/tasks/base/workspaces/zbobr/task-61/zbobr/zbobr/src/init.rs:1120:
         let wf = default_workflow();
         let merge = wf.pipelines.get(&Pipeline::Merge).unwrap();
         let merging = merge.stages.get(&Stage::from("merging")).unwrap();
-        let task_prompt = merging
-            .prompts
-            .as_ref()
-            .and_then(|map| map.get("task"));
+        let task_prompt = merging.prompts.as_ref().and_then(|map| map.get("task"));
         assert_eq!(task_prompt, Some(&TomlOption::ExplicitNone));
     }
 
Diff in /data/home/skynet/tasks/base/workspaces/zbobr/task-61/zbobr/zbobr-repo-backend-github/src/github.rs:1220:
 
         Mock::given(method("GET"))
             .and(path("/repos/org/repo"))
-            .respond_with(ResponseTemplate::new(200).set_body_json(
-                serde_json::json!({
-                    "full_name": "org/repo",
-                    "fork": false
-                }),
-            ))
+            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
+                "full_name": "org/repo",
+                "fork": false
+            })))
             .expect(1)
             .mount(&mock_server)
             .await;
Diff in /data/home/skynet/tasks/base/workspaces/zbobr/task-61/zbobr/zbobr-repo-backend-github/src/github.rs:1232:
 
         Mock::given(method("POST"))
             .and(path("/repos/org/repo/merge-upstream"))
-            .respond_with(ResponseTemplate::new(200).set_body_json(
-                serde_json::json!({
-                    "merge_type": "fast-forward"
-                }),
-            ))
+            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
+                "merge_type": "fast-forward"
+            })))
             .expect(0)
             .mount(&mock_server)
             .await;
Diff in /data/home/skynet/tasks/base/workspaces/zbobr/task-61/zbobr/zbobr-repo-backend-github/src/github.rs:1273:
 
         Mock::given(method("GET"))
             .and(path("/repos/org/repo"))
-            .respond_with(ResponseTemplate::new(200).set_body_json(
-                serde_json::json!({
-                    "full_name": "org/repo",
-                    "fork": true
-                }),
-            ))
+            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
+                "full_name": "org/repo",
+                "fork": true
+            })))
             .expect(1)
             .mount(&mock_server)
             .await;
Diff in /data/home/skynet/tasks/base/workspaces/zbobr/task-61/zbobr/zbobr-repo-backend-github/src/github.rs:1285:
 
         Mock::given(method("POST"))
             .and(path("/repos/org/repo/merge-upstream"))
-            .respond_with(ResponseTemplate::new(200).set_body_json(
-                serde_json::json!({
-                    "merge_type": "fast-forward"
-                }),
-            ))
+            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
+                "merge_type": "fast-forward"
+            })))
             .expect(1)
             .mount(&mock_server)
             .await;
Diff in /data/home/skynet/tasks/base/workspaces/zbobr/task-61/zbobr/zbobr-repo-backend-github/src/github.rs:1326:
 
         Mock::given(method("GET"))
             .and(path("/repos/org/repo"))
-            .respond_with(ResponseTemplate::new(200).set_body_json(
-                serde_json::json!({
-                    "full_name": "org/repo",
-                    "fork": true
-                }),
-            ))
+            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
+                "full_name": "org/repo",
+                "fork": true
+            })))
             .expect(1)
             .mount(&mock_server)
             .await;
Diff in /data/home/skynet/tasks/base/workspaces/zbobr/task-61/zbobr/zbobr-repo-backend-github/src/github.rs:1338:
 
         Mock::given(method("POST"))
             .and(path("/repos/org/repo/merge-upstream"))
-            .respond_with(ResponseTemplate::new(422).set_body_json(
-                serde_json::json!({
-                    "message": "Merge conflict"
-                }),
-            ))
+            .respond_with(ResponseTemplate::new(422).set_body_json(serde_json::json!({
+                "message": "Merge conflict"
+            })))
             .expect(1)
             .mount(&mock_server)
             .await;
Diff in /data/home/skynet/tasks/base/workspaces/zbobr/task-61/zbobr/zbobr-task-backend-github/src/github.rs:94:
 }
 
 fn format_report_filename_timestamp() -> String {
-    chrono::Local::now().format("%Y-%m-%d_%H-%M-%S_%z").to_string()
+    chrono::Local::now()
+        .format("%Y-%m-%d_%H-%M-%S_%z")
+        .to_string()
 }
 
 fn is_transient_octocrab_error(error: &octocrab::Error) -> bool {
Diff in /data/home/skynet/tasks/base/workspaces/zbobr/task-61/zbobr/zbobr-task-backend-github/src/github.rs:1812:
     fn format_report_filename_timestamp_matches_expected_pattern() {
         let timestamp = format_report_filename_timestamp();
 
-        assert_eq!(timestamp.len(), 25, "timestamp should be exactly 25 characters");
+        assert_eq!(
+            timestamp.len(),
+            25,
+            "timestamp should be exactly 25 characters"
+        );
         assert_eq!(timestamp.chars().nth(10), Some('_'));
         assert_eq!(timestamp.chars().nth(19), Some('_'));
         assert!(matches!(timestamp.chars().nth(20), Some('+') | Some('-')));
fmt_status:1
== cargo clippy ==
   Compiling zbobr-macros v0.1.0 (/data/home/skynet/tasks/base/workspaces/zbobr/task-61/zbobr/zbobr-macros)
    Building [======================>  ] 365/394: zbobr-macros, zbobr-macros                                              Building [======================>  ] 366/394: zbobr_macros(test), zbobr-macros                                        Building [======================>  ] 367/394: zbobr-macros                                                            Checking zbobr-utility v0.1.0 (/data/home/skynet/tasks/base/workspaces/zbobr/task-61/zbobr/zbobr-utility)
    Building [======================>  ] 368/394: zbobr_utility(test), zbobr-utility                                  error: this `if` statement can be collapsed
  --> zbobr-utility/src/toml_edit_util.rs:49:5
   |
49 | /     if let Some(Item::Table(parent_table)) = doc.get_mut(parent_table_name) {
50 | |         if let Some(Item::Table(child_table)) = parent_table.get_mut(child_key) {
51 | |             child_table.set_dotted(true);
52 | |         }
53 | |     }
   | |_____^
   |
   = help: for further information visit https://rust-lang.github.io/rust-clippy/rust-1.94.0/index.html#collapsible_if
   = note: `-D clippy::collapsible-if` implied by `-D warnings`
   = help: to override `-D warnings` add `#[allow(clippy::collapsible_if)]`
help: collapse nested if block
   |
49 ~     if let Some(Item::Table(parent_table)) = doc.get_mut(parent_table_name)
50 ~         && let Some(Item::Table(child_table)) = parent_table.get_mut(child_key) {
51 |             child_table.set_dotted(true);
52 ~         }
   |

    Building [======================>  ] 368/394: zbobr_utility(test), zbobr-utility                                  error: this `impl` can be derived
  --> zbobr-utility/src/toml_option.rs:28:1
   |
28 | / impl<T> Default for TomlOption<T> {
29 | |     fn default() -> Self {
30 | |         Self::Absent
31 | |     }
32 | | }
   | |_^
   |
   = help: for further information visit https://rust-lang.github.io/rust-clippy/rust-1.94.0/index.html#derivable_impls
   = note: `-D clippy::derivable-impls` implied by `-D warnings`
   = help: to override `-D warnings` add `#[allow(clippy::derivable_impls)]`
help: replace the manual implementation with a derive attribute and mark the default variant
   |
19 + #[derive(Default)]
20 | pub enum TomlOption<T> {
21 |     /// Field was not present in the TOML source.
22 ~     #[default]
23 ~     Absent,
   |

    Building [======================>  ] 368/394: zbobr_utility(test), zbobr-utility                                  error: could not compile `zbobr-utility` (lib) due to 2 previous errors
warning: build failed, waiting for other jobs to finish...
    Building [======================>  ] 369/394: zbobr_utility(test)                                                 error: could not compile `zbobr-utility` (lib test) due to 2 previous errors
clippy_status:101

Summary:
- cargo fmt reported diffs (fmt_status=1). Files with diffs shown above.
- cargo clippy failed with errors (clippy_status=101). Errors include collapsible if and derivable impls in zbobr-utility crate.

Next steps:
- Apply rustfmt changes shown by cargo fmt.
- Fix clippy diagnostics or add targeted allow attributes if intentional.


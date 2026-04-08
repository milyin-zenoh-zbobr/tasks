Diff in /data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr/src/commands.rs:3:
 use std::{path::PathBuf, sync::Arc};
 
 use clap::Subcommand;
-use zbobr_api::{Pipeline, Stage, WorktreeBackend, config::{Role, StageDefinition, WorkflowConfig}};
+use zbobr_api::{
+    Pipeline, Stage, WorktreeBackend,
+    config::{Role, StageDefinition, WorkflowConfig},
+};
 use zbobr_dispatcher::{
     ConfiguredPromptBuilder, TaskDir, TaskListEntry, VAR_DESTINATION_BRANCH,
-    VAR_DESTINATION_REPOSITORY, Workflow, ZbobrDispatcher, eligible_runnable_tasks,
+    VAR_DESTINATION_REPOSITORY, Workflow, ZbobrDispatcher,
     config::{ZbobrDispatcherConfig, ZbobrExecutorConfig},
-    print_task, sample_task_and_comments, select_runnable_task,
+    eligible_runnable_tasks, print_task, sample_task_and_comments, select_runnable_task,
 };
 use zbobr_executor_claude::ClaudeExecutor;
 use zbobr_executor_copilot::CopilotExecutor;
 Diff in /data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr/src/commands.rs:554:
         }
         (Some(stage), None) => {
             if let Some(p) = pipeline {
-                workflow
-                    .stage(p, stage)
-                    .ok_or_else(|| {
-                        anyhow::anyhow!("Stage '{}' not found in pipeline '{}'", stage, p)
-                    })
+                workflow.stage(p, stage).ok_or_else(|| {
+                    anyhow::anyhow!("Stage '{}' not found in pipeline '{}'", stage, p)
+                })
             } else {
                 let matches: Vec<_> = workflow
                     .all_stages()
 Diff in /data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr/src/commands.rs:590:
                     .values()
                     .find(|s| s.role().map(|r| r.as_str()) == Some(role.as_str()))
                     .ok_or_else(|| {
-                        anyhow::anyhow!(
-                            "No stage with role '{}' found in pipeline '{}'",
-                            role,
-                            p
-                        )
+                        anyhow::anyhow!("No stage with role '{}' found in pipeline '{}'", role, p)
                     })
             } else {
                 workflow
 Diff in /data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr/src/init.rs:7:
 use std::os::unix::fs::PermissionsExt;
 
 use indexmap::IndexMap;
+use zbobr_api::task::{Executor, Model};
 use zbobr_api::{
     Pipeline, Secret, Stage,
     config::{
 Diff in /data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr/src/init.rs:15:
     },
     config_tools::McpTool,
 };
-use zbobr_utility::TomlOption;
-use zbobr_api::task::{Executor, Model};
 use zbobr_dispatcher::config::{ZbobrDispatcherToml, ZbobrExecutorToml};
 use zbobr_executor_copilot::ZbobrExecutorCopilotToml;
 use zbobr_repo_backend_github::ZbobrRepoBackendGithubToml;
 Diff in /data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr/src/init.rs:23:
 use zbobr_task_backend_github::ZbobrTaskBackendGithubToml;
+use zbobr_utility::TomlOption;
 
 use super::RootConfigToml;
 
 Diff in /data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs:1:
 +use std::collections::HashMap;
 use std::path::{Path, PathBuf};
 -use std::{collections::HashMap};
 
 use indexmap::IndexMap;
 use zbobr_utility::MergeToml;
 Diff in /data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs:9:
 use crate::task::FixedOffsetTz;
 use crate::{
     config_tools::McpTool,
-    task::{Model, Pipeline, Executor},
+    task::{Executor, Model, Pipeline},
 };
 use zbobr_utility::Secret;
 
 Diff in /data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs:549:
         let resolved_prompts_dir = self
             .prompts_dir
             .map(|p| zbobr_utility::resolve_path(p, config_dir));
-        let prompt_base: &Path = resolved_prompts_dir.as_option().map(|p| p.as_path()).unwrap_or(config_dir);
+        let prompt_base: &Path = resolved_prompts_dir
+            .as_option()
+            .map(|p| p.as_path())
+            .unwrap_or(config_dir);
         let prompts = self.prompts.map(|map| {
             map.into_iter()
                 .map(|(k, v)| (k, v.map(|p| zbobr_utility::resolve_path(p, prompt_base))))
 Diff in /data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs:956:
         visited: &mut Vec<Provider>,
     ) -> anyhow::Result<ResolvedProvider> {
         if visited.contains(&provider) {
-            anyhow::bail!("Circular parent reference detected in provider '{}'", provider.as_str());
+            anyhow::bail!(
+                "Circular parent reference detected in provider '{}'",
+                provider.as_str()
+            );
         }
         visited.push(provider.clone());
 
 Diff in /data/home/skynet/tasks/workspaces/zbobr/task-55/zbobr/zbobr-api/src/config/mod.rs:1034:
     #[test]
     fn resolve_providers_basic() {
         let mut providers = IndexMap::new();
-        providers.insert(Provider::new("claude"),
+        providers.insert(
+            Provider::new("claude"),
             ProviderDefinition {
                 executor: Some(Executor("claude".to_string())).into(),
                 parent: Default::default(),
 ...
[truncated for brevity in this brief — full report attached]

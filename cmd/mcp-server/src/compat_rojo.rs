use std::sync::Arc;

use crate::adapters::ProjectAdapter;
use crate::config::Config;
#[cfg(feature = "rojo-compat")]
use crate::project_snapshot::{AdapterNode, ProjectSnapshot};
#[cfg(feature = "rojo-compat")]
use crate::adapters::ResolvedProjectTarget;

#[cfg(feature = "rojo-compat")]
use anyhow::Result as AnyResult;

#[cfg(feature = "rojo-compat")]
use serde_json::Value;

#[cfg(feature = "rojo-compat")]
use std::collections::HashMap;

#[cfg(feature = "rojo-compat")]
use rojo_adapter::RojoAdapter;

#[cfg(feature = "rojo-compat")]
fn convert_snapshot(snapshot: rojo_adapter::ProjectSnapshot) -> ProjectSnapshot {
    let instances = snapshot
        .instances
        .into_iter()
        .map(|(id, node)| {
            (
                id,
                AdapterNode {
                    id: node.id,
                    parent: node.parent,
                    name: node.name,
                    class_name: node.class_name,
                    properties: node.properties,
                    children: node.children,
                },
            )
        })
        .collect::<HashMap<_, _>>();

    ProjectSnapshot {
        root_id: snapshot.root_id,
        instances,
        file_paths: snapshot.file_paths,
    }
}

#[cfg(feature = "rojo-compat")]
struct RojoCompatibilityAdapter {
    inner: RojoAdapter,
}

#[cfg(feature = "rojo-compat")]
impl RojoCompatibilityAdapter {
    fn new() -> Self {
        Self {
            inner: RojoAdapter::new(),
        }
    }
}

#[cfg(feature = "rojo-compat")]
impl ProjectAdapter for RojoCompatibilityAdapter {
    fn resolve_project_target(&self, requested_path: &str) -> Result<ResolvedProjectTarget, String> {
        let requested = if requested_path.trim().is_empty() {
            "src".to_string()
        } else {
            requested_path.trim().to_string()
        };

        Ok(ResolvedProjectTarget {
            requested_path: requested.clone(),
            adapter_project_path: requested,
            compatibility_mode: "rojo-direct".to_string(),
            native_manifest_path: None,
            project_name: None,
        })
    }

    fn open_session(&self, project_path: &str) -> AnyResult<Value> {
        self.inner.open_session(project_path)
    }

    fn snapshot_project(&self, project_path: &str) -> AnyResult<ProjectSnapshot> {
        self.inner.snapshot_project(project_path).map(convert_snapshot)
    }
}

#[cfg(feature = "rojo-compat")]
pub fn maybe_select_rojo_adapter(
    config: &Config,
    mode: &str,
) -> Option<(Arc<dyn ProjectAdapter>, &'static str)> {
    if !config.enable_rojo_adapter_mode {
        return None;
    }

    match mode {
        "rojo" => Some((Arc::new(RojoCompatibilityAdapter::new()), "rojo")),
        "auto" if !config.enable_native_project_manifest => {
            Some((Arc::new(RojoCompatibilityAdapter::new()), "rojo"))
        }
        _ => None,
    }
}

#[cfg(not(feature = "rojo-compat"))]
pub fn maybe_select_rojo_adapter(
    _config: &Config,
    _mode: &str,
) -> Option<(Arc<dyn ProjectAdapter>, &'static str)> {
    None
}

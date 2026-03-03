use anyhow::Result as AnyResult;
use rojo_adapter::RojoAdapter;
use serde_json::Value;
use std::sync::Arc;

use crate::adapters::{ProjectAdapter, ResolvedProjectTarget};
use crate::config::Config;

struct RojoCompatibilityAdapter {
    inner: RojoAdapter,
}

impl RojoCompatibilityAdapter {
    fn new() -> Self {
        Self {
            inner: RojoAdapter::new(),
        }
    }
}

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

    fn snapshot_project(&self, project_path: &str) -> AnyResult<rojo_adapter::ProjectSnapshot> {
        self.inner.snapshot_project(project_path)
    }
}

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

use anyhow::Result as AnyResult;
use rojo_adapter::RojoAdapter;
use serde::Deserialize;
use serde_json::Value;
use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
    sync::Arc,
};

use crate::config::Config;

#[derive(Debug, Deserialize, Default)]
struct AdrabloxManifestCompatibility {
    #[serde(rename = "rojoProjectPath")]
    rojo_project_path: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
struct AdrabloxManifestSession {
    #[serde(rename = "defaultProjectPath")]
    default_project_path: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
struct AdrabloxProjectManifest {
    name: Option<String>,
    #[serde(default)]
    compatibility: AdrabloxManifestCompatibility,
    #[serde(default)]
    session: AdrabloxManifestSession,
}

#[derive(Debug, Clone)]
pub struct ResolvedProjectTarget {
    pub requested_path: String,
    pub adapter_project_path: String,
    pub compatibility_mode: String,
    pub native_manifest_path: Option<String>,
    pub project_name: Option<String>,
}

pub trait ProjectAdapter: Send + Sync {
    fn resolve_project_target(&self, requested_path: &str) -> Result<ResolvedProjectTarget, String>;
    fn open_session(&self, project_path: &str) -> AnyResult<Value>;
    fn snapshot_project(&self, project_path: &str) -> AnyResult<rojo_adapter::ProjectSnapshot>;
}

struct NativeManifestAdapter {
    enable_native_project_manifest: bool,
    native_project_manifest_path: String,
}

#[derive(Debug, Clone)]
struct NativePathBinding {
    instance_id: String,
    source_root: PathBuf,
}

impl NativeManifestAdapter {
    fn new(
        enable_native_project_manifest: bool,
        native_project_manifest_path: String,
    ) -> Self {
        Self {
            enable_native_project_manifest,
            native_project_manifest_path,
        }
    }

    fn load_adrablox_manifest(&self) -> Result<AdrabloxProjectManifest, String> {
        let content = fs::read_to_string(&self.native_project_manifest_path).map_err(|err| {
            format!(
                "failed to read native manifest {}: {}",
                self.native_project_manifest_path, err
            )
        })?;
        serde_json::from_str::<AdrabloxProjectManifest>(&content).map_err(|err| {
            format!(
                "failed to parse native manifest {}: {}",
                self.native_project_manifest_path, err
            )
        })
    }

    fn resolve_relative_candidate(project_path: &str) -> AnyResult<PathBuf> {
        let cwd = std::env::current_dir()?;
        let direct = cwd.join(project_path);
        if direct.exists() {
            return Ok(direct);
        }

        for ancestor in cwd.ancestors().skip(1) {
            let joined = ancestor.join(project_path);
            if joined.exists() {
                return Ok(joined);
            }
        }

        if let Some(repo_like_root) = cwd
            .ancestors()
            .find(|ancestor| ancestor.join("Cargo.toml").is_file() || ancestor.join(".git").exists())
        {
            return Ok(repo_like_root.join(project_path));
        }

        Ok(direct)
    }

    fn resolve_project_file(project_path: &str) -> AnyResult<PathBuf> {
        let candidate = PathBuf::from(project_path);
        if candidate.is_absolute() {
            return Ok(candidate);
        }

        Self::resolve_relative_candidate(project_path)
    }

    fn resolve_source_root(&self, project_path: &str) -> AnyResult<PathBuf> {
        let candidate = Self::resolve_project_file(project_path)?;

        let source_root = if candidate.exists() {
            if candidate.is_dir() {
                candidate
            } else {
                let parent = candidate.parent().unwrap_or_else(|| Path::new(".")).to_path_buf();
                let parent_src = parent.join("src");
                if parent_src.exists() && parent_src.is_dir() {
                    parent_src
                } else {
                    parent
                }
            }
        } else if project_path.ends_with(".project.json") {
            self.resolve_native_source_root(project_path)?
        } else {
            candidate
        };

        Ok(source_root)
    }

    fn snapshot_project_native(&self, project_path: &str) -> AnyResult<rojo_adapter::ProjectSnapshot> {
        let project_file = Self::resolve_project_file(project_path)?;
        let project_dir = project_file
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .to_path_buf();
        let content = fs::read_to_string(&project_file)?;
        let project_json: serde_json::Value = serde_json::from_str(&content)?;
        let tree = project_json
            .get("tree")
            .and_then(serde_json::Value::as_object)
            .ok_or_else(|| anyhow::anyhow!("project file missing tree object"))?;

        let root_id = "ref_root".to_string();
        let mut instances: HashMap<String, rojo_adapter::AdapterNode> = HashMap::new();
        let mut file_paths: HashMap<String, String> = HashMap::new();
        let mut bindings: Vec<NativePathBinding> = vec![];

        instances.insert(
            root_id.clone(),
            rojo_adapter::AdapterNode {
                id: root_id.clone(),
                parent: None,
                name: "Game".to_string(),
                class_name: "DataModel".to_string(),
                properties: serde_json::Map::new(),
                children: vec![],
            },
        );

        collect_tree_bindings(
            tree,
            &root_id,
            &project_dir,
            &mut instances,
            &mut bindings,
        );

        for binding in &bindings {
            add_files_from_source_root(
                &mut instances,
                &mut file_paths,
                &binding.instance_id,
                &binding.source_root,
            )?;
        }

        Ok(rojo_adapter::ProjectSnapshot {
            root_id,
            instances,
            file_paths,
        })
    }

    fn open_session_native(&self, project_path: &str) -> AnyResult<Value> {
        let source_root = self.resolve_source_root(project_path)?;
        let session_path = source_root.to_string_lossy().replace('\\', "/");
        let session_id = format!("sess:{}", sanitize_path_component(&session_path));

        Ok(serde_json::json!({
            "sessionId": session_id,
            "rootInstanceId": "ref_root",
            "initialCursor": "0",
            "sourceRoot": source_root.to_string_lossy()
        }))
    }

    fn resolve_native_source_root(&self, project_path: &str) -> AnyResult<PathBuf> {
        let project_file = Self::resolve_project_file(project_path)?;
        let project_dir = project_file
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .to_path_buf();
        let content = fs::read_to_string(&project_file)?;
        let project_json: serde_json::Value = serde_json::from_str(&content)?;
        let tree = project_json
            .get("tree")
            .and_then(serde_json::Value::as_object)
            .ok_or_else(|| anyhow::anyhow!("project file missing tree object"))?;

        let mut mapped_roots: Vec<PathBuf> = vec![];
        collect_project_paths(tree, &project_dir, &mut mapped_roots);

        if mapped_roots.is_empty() {
            let fallback_src = project_dir.join("src");
            if fallback_src.exists() && fallback_src.is_dir() {
                return Ok(fallback_src);
            }
            return Ok(project_dir);
        }

        Ok(common_ancestor_path(&mapped_roots).unwrap_or(project_dir))
    }

    fn snapshot_project_from_source_root(
        &self,
        project_path: &str,
    ) -> AnyResult<rojo_adapter::ProjectSnapshot> {
        let source_root = self.resolve_source_root(project_path)?;
        let root_id = "ref_root".to_string();
        let server_script_service_id = "ref_server_script_service".to_string();

        let mut instances: HashMap<String, rojo_adapter::AdapterNode> = HashMap::new();
        instances.insert(
            root_id.clone(),
            rojo_adapter::AdapterNode {
                id: root_id.clone(),
                parent: None,
                name: "Game".to_string(),
                class_name: "DataModel".to_string(),
                properties: serde_json::Map::new(),
                children: vec![server_script_service_id.clone()],
            },
        );

        instances.insert(
            server_script_service_id.clone(),
            rojo_adapter::AdapterNode {
                id: server_script_service_id.clone(),
                parent: Some(root_id.clone()),
                name: "ServerScriptService".to_string(),
                class_name: "ServerScriptService".to_string(),
                properties: serde_json::Map::new(),
                children: vec![],
            },
        );

        let mut file_paths: HashMap<String, String> = HashMap::new();
        add_files_from_source_root(
            &mut instances,
            &mut file_paths,
            &server_script_service_id,
            &source_root,
        )?;

        Ok(rojo_adapter::ProjectSnapshot {
            root_id,
            instances,
            file_paths,
        })
    }
}

impl ProjectAdapter for RojoAdapter {
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
        RojoAdapter::open_session(self, project_path)
    }

    fn snapshot_project(&self, project_path: &str) -> AnyResult<rojo_adapter::ProjectSnapshot> {
        RojoAdapter::snapshot_project(self, project_path)
    }
}

impl ProjectAdapter for NativeManifestAdapter {
    fn resolve_project_target(&self, requested_path: &str) -> Result<ResolvedProjectTarget, String> {
        let requested = if requested_path.trim().is_empty() {
            "src".to_string()
        } else {
            requested_path.trim().to_string()
        };

        if !self.enable_native_project_manifest {
            return Ok(ResolvedProjectTarget {
                requested_path: requested.clone(),
                adapter_project_path: requested,
                compatibility_mode: "native-direct".to_string(),
                native_manifest_path: None,
                project_name: None,
            });
        }

        let requested_is_manifest = requested.eq_ignore_ascii_case("adrablox.project.json")
            || requested.eq_ignore_ascii_case(&self.native_project_manifest_path);
        let requested_is_legacy_default = requested.eq_ignore_ascii_case("default.project.json")
            || requested.eq_ignore_ascii_case("src");

        if requested_is_manifest || requested_is_legacy_default {
            match self.load_adrablox_manifest() {
                Ok(manifest) => {
                    let adapter_project_path = manifest
                        .session
                        .default_project_path
                        .or(manifest.compatibility.rojo_project_path)
                        .unwrap_or_else(|| "default.project.json".to_string());

                    return Ok(ResolvedProjectTarget {
                        requested_path: requested,
                        adapter_project_path,
                        compatibility_mode: "native-manifest".to_string(),
                        native_manifest_path: Some(self.native_project_manifest_path.clone()),
                        project_name: manifest.name,
                    });
                }
                Err(err) if requested_is_manifest => {
                    return Err(err);
                }
                Err(_) => {}
            }
        }

        Ok(ResolvedProjectTarget {
            requested_path: requested.clone(),
            adapter_project_path: requested,
            compatibility_mode: "native-direct".to_string(),
            native_manifest_path: None,
            project_name: None,
        })
    }

    fn open_session(&self, project_path: &str) -> AnyResult<Value> {
        self.open_session_native(project_path)
    }

    fn snapshot_project(&self, project_path: &str) -> AnyResult<rojo_adapter::ProjectSnapshot> {
        if project_path.ends_with(".project.json") {
            return self.snapshot_project_native(project_path);
        }

        self.snapshot_project_from_source_root(project_path)
    }
}

fn collect_tree_bindings(
    tree_node: &serde_json::Map<String, serde_json::Value>,
    parent_id: &str,
    project_dir: &Path,
    instances: &mut HashMap<String, rojo_adapter::AdapterNode>,
    bindings: &mut Vec<NativePathBinding>,
) {
    for (name, raw_child) in tree_node {
        if name.starts_with('$') {
            continue;
        }

        let Some(child_obj) = raw_child.as_object() else {
            continue;
        };

        let class_name = child_obj
            .get("$className")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("Folder")
            .to_string();
        let child_id = format!(
            "ref_tree_{}_{}",
            sanitize_path_component(parent_id),
            sanitize_path_component(name)
        );

        if !instances.contains_key(&child_id) {
            instances.insert(
                child_id.clone(),
                rojo_adapter::AdapterNode {
                    id: child_id.clone(),
                    parent: Some(parent_id.to_string()),
                    name: name.to_string(),
                    class_name,
                    properties: serde_json::Map::new(),
                    children: vec![],
                },
            );
            append_child(instances, parent_id, &child_id);
        }

        if let Some(path_str) = child_obj.get("$path").and_then(serde_json::Value::as_str) {
            bindings.push(NativePathBinding {
                instance_id: child_id.clone(),
                source_root: project_dir.join(path_str),
            });
        }

        collect_tree_bindings(child_obj, &child_id, project_dir, instances, bindings);
    }
}

fn collect_project_paths(
    tree_node: &serde_json::Map<String, serde_json::Value>,
    project_dir: &Path,
    out: &mut Vec<PathBuf>,
) {
    for (name, raw_child) in tree_node {
        if name.starts_with('$') {
            continue;
        }

        let Some(child_obj) = raw_child.as_object() else {
            continue;
        };

        if let Some(path_str) = child_obj.get("$path").and_then(serde_json::Value::as_str) {
            out.push(project_dir.join(path_str));
        }

        collect_project_paths(child_obj, project_dir, out);
    }
}

fn common_ancestor_path(paths: &[PathBuf]) -> Option<PathBuf> {
    let first = paths.first()?;
    let mut base = first.canonicalize().unwrap_or_else(|_| first.clone());

    for path in paths.iter().skip(1) {
        let current = path.canonicalize().unwrap_or_else(|_| path.clone());
        while !current.starts_with(&base) {
            if !base.pop() {
                return None;
            }
        }
    }

    Some(base)
}

fn add_files_from_source_root(
    instances: &mut HashMap<String, rojo_adapter::AdapterNode>,
    file_paths: &mut HashMap<String, String>,
    mapping_root_id: &str,
    source_root: &Path,
) -> AnyResult<()> {
    if !source_root.exists() || !source_root.is_dir() {
        return Ok(());
    }

    walk_source_tree(instances, file_paths, mapping_root_id, source_root, source_root)
}

fn walk_source_tree(
    instances: &mut HashMap<String, rojo_adapter::AdapterNode>,
    file_paths: &mut HashMap<String, String>,
    mapping_root_id: &str,
    source_root: &Path,
    current_dir: &Path,
) -> AnyResult<()> {
    for entry in fs::read_dir(current_dir)? {
        let entry = entry?;
        let path = entry.path();
        let metadata = entry.metadata()?;

        if metadata.is_dir() {
            walk_source_tree(instances, file_paths, mapping_root_id, source_root, &path)?;
            continue;
        }

        if !metadata.is_file() || !is_script_file(&path) {
            continue;
        }

        let relative = match path.strip_prefix(source_root) {
            Ok(value) => value,
            Err(_) => continue,
        };

        let parent_id = ensure_folder_chain(instances, mapping_root_id, relative.parent());
        let (name, class_name) = classify_file(&path);
        let source = fs::read_to_string(&path).unwrap_or_default();
        let file_id = format!(
            "ref_file_{}_{}",
            sanitize_path_component(mapping_root_id),
            sanitize_path_component(&relative.to_string_lossy())
        );

        let mut properties = serde_json::Map::new();
        properties.insert("Source".to_string(), serde_json::Value::String(source));

        instances.insert(
            file_id.clone(),
            rojo_adapter::AdapterNode {
                id: file_id.clone(),
                parent: Some(parent_id.clone()),
                name,
                class_name,
                properties,
                children: vec![],
            },
        );
        append_child(instances, &parent_id, &file_id);
        file_paths.insert(file_id, canonical_path_string(&path));
    }

    Ok(())
}

fn is_script_file(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| ext.eq_ignore_ascii_case("lua") || ext.eq_ignore_ascii_case("luau"))
        .unwrap_or(false)
}

fn classify_file(path: &Path) -> (String, String) {
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("Script.lua");

    if let Some(stripped) = file_name.strip_suffix(".module.lua") {
        return (stripped.to_string(), "ModuleScript".to_string());
    }

    if let Some(stripped) = file_name.strip_suffix(".server.lua") {
        return (stripped.to_string(), "Script".to_string());
    }

    if let Some(stripped) = file_name.strip_suffix(".client.lua") {
        return (stripped.to_string(), "LocalScript".to_string());
    }

    if let Some(stripped) = file_name.strip_suffix(".lua") {
        return (stripped.to_string(), "ModuleScript".to_string());
    }

    (file_name.to_string(), "ModuleScript".to_string())
}

fn ensure_folder_chain(
    instances: &mut HashMap<String, rojo_adapter::AdapterNode>,
    root_parent_id: &str,
    relative_parent: Option<&Path>,
) -> String {
    let mut parent_id = root_parent_id.to_string();

    let Some(relative_parent) = relative_parent else {
        return parent_id;
    };

    for component in relative_parent.components() {
        let name = component.as_os_str().to_string_lossy().to_string();
        if name.is_empty() {
            continue;
        }

        let folder_id = format!(
            "ref_folder_{}_{}",
            sanitize_path_component(&parent_id),
            sanitize_path_component(&name)
        );

        if !instances.contains_key(&folder_id) {
            instances.insert(
                folder_id.clone(),
                rojo_adapter::AdapterNode {
                    id: folder_id.clone(),
                    parent: Some(parent_id.clone()),
                    name,
                    class_name: "Folder".to_string(),
                    properties: serde_json::Map::new(),
                    children: vec![],
                },
            );
            append_child(instances, &parent_id, &folder_id);
        }

        parent_id = folder_id;
    }

    parent_id
}

fn append_child(instances: &mut HashMap<String, rojo_adapter::AdapterNode>, parent_id: &str, child_id: &str) {
    if let Some(parent) = instances.get_mut(parent_id) {
        if !parent.children.iter().any(|existing| existing == child_id) {
            parent.children.push(child_id.to_string());
        }
    }
}

fn sanitize_path_component(value: &str) -> String {
    value.replace([':', '\\', '/', '.', '-', ' '], "_")
}

fn canonical_path_string(path: &Path) -> String {
    path.canonicalize()
        .unwrap_or_else(|_| path.to_path_buf())
        .to_string_lossy()
        .to_string()
}

pub fn select_project_adapter(config: &Config) -> (Arc<dyn ProjectAdapter>, &'static str) {
    let mode = config.project_adapter_mode.trim().to_ascii_lowercase();
    match mode.as_str() {
        "rojo" => {
            if config.enable_rojo_adapter_mode {
                (Arc::new(RojoAdapter::new()), "rojo")
            } else {
                (
                    Arc::new(NativeManifestAdapter::new(
                        config.enable_native_project_manifest,
                        config.native_project_manifest_path.clone(),
                    )),
                    "native",
                )
            }
        }
        "native" => (
            Arc::new(NativeManifestAdapter::new(
                config.enable_native_project_manifest,
                config.native_project_manifest_path.clone(),
            )),
            "native",
        ),
        _ => {
            if config.enable_native_project_manifest {
                (
                    Arc::new(NativeManifestAdapter::new(
                        config.enable_native_project_manifest,
                        config.native_project_manifest_path.clone(),
                    )),
                    "native",
                )
            } else {
                (Arc::new(RojoAdapter::new()), "rojo")
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{select_project_adapter, NativeManifestAdapter, ProjectAdapter};
    use crate::config::Config;
    use std::{env, fs};

    fn base_config() -> Config {
        Config {
            bind_addr: "127.0.0.1:44877".to_string(),
            project_adapter_mode: "auto".to_string(),
            enable_rojo_adapter_mode: false,
            enable_legacy_rojo_routes: false,
            enable_native_project_manifest: false,
            native_project_manifest_path: "adrablox.project.json".to_string(),
            enable_ws_rpc: true,
            require_ws_token: false,
            ws_auth_token: None,
            ws_backpressure_policy: "drop_oldest".to_string(),
            ws_ping_interval_ms: 30_000,
            ws_ping_timeout_ms: 60_000,
            max_ws_message_size: 1_048_576,
            client_send_queue_capacity: 256,
            seq_retention: 10_000,
        }
    }

    #[test]
    fn select_adapter_explicit_rojo_mode() {
        let mut cfg = base_config();
        cfg.project_adapter_mode = "rojo".to_string();
        cfg.enable_rojo_adapter_mode = true;
        cfg.enable_native_project_manifest = true;

        let (_adapter, kind) = select_project_adapter(&cfg);
        assert_eq!(kind, "rojo");
    }

    #[test]
    fn select_adapter_explicit_rojo_mode_is_gated_when_disabled() {
        let mut cfg = base_config();
        cfg.project_adapter_mode = "rojo".to_string();
        cfg.enable_rojo_adapter_mode = false;
        cfg.enable_native_project_manifest = false;

        let (_adapter, kind) = select_project_adapter(&cfg);
        assert_eq!(kind, "native");
    }

    #[test]
    fn select_adapter_explicit_native_mode() {
        let mut cfg = base_config();
        cfg.project_adapter_mode = "native".to_string();
        cfg.enable_native_project_manifest = false;

        let (_adapter, kind) = select_project_adapter(&cfg);
        assert_eq!(kind, "native");
    }

    #[test]
    fn select_adapter_auto_mode_prefers_native_when_enabled() {
        let mut cfg = base_config();
        cfg.project_adapter_mode = "auto".to_string();
        cfg.enable_native_project_manifest = true;

        let (_adapter, kind) = select_project_adapter(&cfg);
        assert_eq!(kind, "native");
    }

    #[test]
    fn select_adapter_auto_mode_falls_back_to_rojo_when_disabled() {
        let mut cfg = base_config();
        cfg.project_adapter_mode = "auto".to_string();
        cfg.enable_native_project_manifest = false;

        let (_adapter, kind) = select_project_adapter(&cfg);
        assert_eq!(kind, "rojo");
    }

    #[test]
    fn native_adapter_errors_for_explicit_manifest_when_missing() {
        let unique = format!(
            "adrablox_missing_manifest_{}_{}.json",
            std::process::id(),
            std::thread::current().name().unwrap_or("t")
        );
        let manifest_path = env::temp_dir().join(unique);
        if manifest_path.exists() {
            let _ = fs::remove_file(&manifest_path);
        }

        let adapter = NativeManifestAdapter::new(true, manifest_path.to_string_lossy().to_string());
        let result = adapter.resolve_project_target("adrablox.project.json");
        assert!(result.is_err());
    }

    #[test]
    fn native_adapter_uses_manifest_default_project_path() {
        let unique = format!("adrablox_manifest_{}_{}.json", std::process::id(), "resolve");
        let manifest_path = env::temp_dir().join(unique);
        let manifest = r#"{
  "name": "TestProj",
  "session": {
    "defaultProjectPath": "default.project.json"
  }
}"#;
        fs::write(&manifest_path, manifest).expect("write manifest");

        let adapter = NativeManifestAdapter::new(true, manifest_path.to_string_lossy().to_string());
        let resolved = adapter
            .resolve_project_target("adrablox.project.json")
            .expect("resolve project target");

        assert_eq!(resolved.adapter_project_path, "default.project.json");
        assert_eq!(resolved.compatibility_mode, "native-manifest");
        assert_eq!(resolved.project_name.as_deref(), Some("TestProj"));

        let _ = fs::remove_file(&manifest_path);
    }

    #[test]
    fn native_adapter_falls_back_to_compatibility_rojo_project_path() {
        let unique = format!("adrablox_manifest_{}_{}.json", std::process::id(), "compat");
        let manifest_path = env::temp_dir().join(unique);
        let manifest = r#"{
  "name": "CompatOnly",
  "compatibility": {
    "rojoProjectPath": "default.project.json"
  }
}"#;
        fs::write(&manifest_path, manifest).expect("write manifest");

        let adapter = NativeManifestAdapter::new(true, manifest_path.to_string_lossy().to_string());
        let resolved = adapter
            .resolve_project_target("adrablox.project.json")
            .expect("resolve project target");

        assert_eq!(resolved.adapter_project_path, "default.project.json");
        assert_eq!(resolved.compatibility_mode, "native-manifest");
        assert_eq!(resolved.project_name.as_deref(), Some("CompatOnly"));

        let _ = fs::remove_file(&manifest_path);
    }

    #[test]
    fn native_adapter_falls_back_to_default_project_json_when_manifest_paths_absent() {
        let unique = format!("adrablox_manifest_{}_{}.json", std::process::id(), "fallback");
        let manifest_path = env::temp_dir().join(unique);
        let manifest = r#"{
  "name": "FallbackOnly"
}"#;
        fs::write(&manifest_path, manifest).expect("write manifest");

        let adapter = NativeManifestAdapter::new(true, manifest_path.to_string_lossy().to_string());
        let resolved = adapter
            .resolve_project_target("adrablox.project.json")
            .expect("resolve project target");

        assert_eq!(resolved.adapter_project_path, "default.project.json");
        assert_eq!(resolved.compatibility_mode, "native-manifest");
        assert_eq!(resolved.project_name.as_deref(), Some("FallbackOnly"));

        let _ = fs::remove_file(&manifest_path);
    }

        #[test]
        fn native_snapshot_reads_mapped_paths_without_rojo() {
                let unique = format!("adrablox_native_snapshot_{}", std::process::id());
                let root = env::temp_dir().join(unique);
                let workspace_dir = root.join("src").join("workspace");
                let shared_dir = root.join("src").join("shared");
                fs::create_dir_all(&workspace_dir).expect("create workspace dir");
                fs::create_dir_all(&shared_dir).expect("create shared dir");

                let ws_file = workspace_dir.join("Hello.server.lua");
                let shared_file = shared_dir.join("Data.module.lua");
                fs::write(&ws_file, "print('workspace')").expect("write workspace file");
                fs::write(&shared_file, "return {}\n").expect("write shared file");

                let project_file = root.join("default.project.json");
                let project_json = r#"{
    "name": "TestNative",
    "tree": {
        "$className": "DataModel",
        "Workspace": {
            "$className": "Workspace",
            "$path": "src/workspace"
        },
        "ReplicatedStorage": {
            "$className": "ReplicatedStorage",
            "$path": "src/shared"
        }
    }
}"#;
                fs::write(&project_file, project_json).expect("write project file");

                let adapter = NativeManifestAdapter::new(true, "adrablox.project.json".to_string());
                let snapshot = adapter
                        .snapshot_project_native(&project_file.to_string_lossy())
                        .expect("native snapshot");

                assert_eq!(snapshot.root_id, "ref_root");
                assert!(snapshot.file_paths.len() >= 2);

                let names: Vec<String> = snapshot.instances.values().map(|n| n.name.clone()).collect();
                assert!(names.iter().any(|name| name == "Hello"));
                assert!(names.iter().any(|name| name == "Data"));

                let _ = fs::remove_dir_all(&root);
        }

        #[test]
        fn native_open_session_uses_common_mapped_root() {
                let unique = format!("adrablox_native_open_{}", std::process::id());
                let root = env::temp_dir().join(unique);
                let workspace_dir = root.join("src").join("workspace");
                let shared_dir = root.join("src").join("shared");
                fs::create_dir_all(&workspace_dir).expect("create workspace dir");
                fs::create_dir_all(&shared_dir).expect("create shared dir");

                let project_file = root.join("default.project.json");
                let project_json = r#"{
    "name": "TestNativeOpen",
    "tree": {
        "$className": "DataModel",
        "Workspace": {
            "$className": "Workspace",
            "$path": "src/workspace"
        },
        "ReplicatedStorage": {
            "$className": "ReplicatedStorage",
            "$path": "src/shared"
        }
    }
}"#;
                fs::write(&project_file, project_json).expect("write project file");

                let adapter = NativeManifestAdapter::new(true, "adrablox.project.json".to_string());
                let open = adapter
                        .open_session_native(&project_file.to_string_lossy())
                        .expect("open session native");

                let source_root = open
                        .get("sourceRoot")
                        .and_then(serde_json::Value::as_str)
                        .unwrap_or_default()
                        .replace('\\', "/");
                assert!(source_root.ends_with("/src"));

                let _ = fs::remove_dir_all(&root);
        }

            #[test]
            fn native_mode_returns_error_on_project_file_error() {
                let adapter = NativeManifestAdapter::new(true, "adrablox.project.json".to_string());

                let open = adapter.open_session("missing.project.json");
                assert!(open.is_err());

                let snapshot = adapter.snapshot_project("missing.project.json");
                assert!(snapshot.is_err());
            }
}
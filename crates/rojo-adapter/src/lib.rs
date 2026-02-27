use anyhow::Result;
use librojo::{snapshot_from_vfs, InstanceContext, InstanceMetadata, InstanceSnapshot, Project, DEFAULT_PROJECT_NAMES};
use memofs::Vfs;
use serde::Serialize;
use serde_json::{Map, Value};
use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
};
use walkdir::WalkDir;

#[derive(Debug, Clone, Serialize)]
pub struct AdapterNode {
    #[serde(rename = "Id")]
    pub id: String,
    #[serde(rename = "Parent")]
    pub parent: Option<String>,
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "ClassName")]
    pub class_name: String,
    #[serde(rename = "Properties")]
    pub properties: Map<String, Value>,
    #[serde(rename = "Children")]
    pub children: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct ProjectSnapshot {
    pub root_id: String,
    pub instances: HashMap<String, AdapterNode>,
    pub file_paths: HashMap<String, String>,
}

#[derive(Debug, Clone)]
pub struct RojoAdapter;

impl Default for RojoAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl RojoAdapter {
    pub fn new() -> Self {
        Self
    }

    pub fn open_session(&self, project_path: &str) -> Result<Value> {
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

    pub fn read_tree(&self, session_id: &str, instance_id: Option<&str>) -> Result<Value> {
        let requested_instance = instance_id.unwrap_or("ref_root");

        Ok(serde_json::json!({
            "sessionId": session_id,
            "cursor": "0",
            "instance": {
                "Id": requested_instance,
                "ClassName": if requested_instance == "ref_root" { "DataModel" } else { "Folder" },
                "Name": if requested_instance == "ref_root" { "Game" } else { "Node" },
                "Properties": {},
                "Children": ["ref_replicated_storage", "ref_server_script_service"]
            },
            "instances": {
                "ref_replicated_storage": {
                    "Id": "ref_replicated_storage",
                    "ClassName": "ReplicatedStorage",
                    "Name": "ReplicatedStorage",
                    "Properties": {},
                    "Children": []
                },
                "ref_server_script_service": {
                    "Id": "ref_server_script_service",
                    "ClassName": "ServerScriptService",
                    "Name": "ServerScriptService",
                    "Properties": {},
                    "Children": []
                }
            }
        }))
    }

    pub fn subscribe_changes(&self, session_id: &str, cursor: Option<&str>) -> Result<Value> {
        let next_cursor = cursor
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(0)
            + 1;

        Ok(serde_json::json!({
            "sessionId": session_id,
            "cursor": next_cursor.to_string(),
            "added": {},
            "updated": [],
            "removed": []
        }))
    }

    pub fn resolve_source_root(&self, project_path: &str) -> Result<PathBuf> {
        let cwd = std::env::current_dir()?;
        let mut candidate = PathBuf::from(project_path);
        if !candidate.is_absolute() {
            candidate = cwd.join(candidate);
        }

        let source_root = if candidate.exists() {
            if candidate.is_dir() {
                candidate
            } else {
                let parent = candidate.parent().unwrap_or(cwd.as_path());
                let parent_src = parent.join("src");
                if parent_src.exists() && parent_src.is_dir() {
                    parent_src
                } else {
                    parent.to_path_buf()
                }
            }
        } else if project_path.ends_with(".project.json") {
            let fallback = cwd.join("src");
            if fallback.exists() && fallback.is_dir() {
                fallback
            } else {
                cwd
            }
        } else {
            candidate
        };

        Ok(source_root)
    }

    pub fn snapshot_project(&self, project_path: &str) -> Result<ProjectSnapshot> {
        if let Some(project_file_path) = self.resolve_rojo_project_file(project_path)? {
            if let Ok(Some(snapshot)) = self.snapshot_from_rojo_project(&project_file_path) {
                return Ok(self.project_snapshot_from_rojo_snapshot(snapshot));
            }
        }

        self.snapshot_project_from_source_tree(project_path)
    }

    fn snapshot_project_from_source_tree(&self, project_path: &str) -> Result<ProjectSnapshot> {
        let source_root = self.resolve_source_root(project_path)?;

        let root_id = "ref_root".to_string();
        let server_script_service_id = "ref_server_script_service".to_string();

        let mut instances = HashMap::new();
        instances.insert(
            root_id.clone(),
            AdapterNode {
                id: root_id.clone(),
                parent: None,
                name: "Game".to_string(),
                class_name: "DataModel".to_string(),
                properties: Map::new(),
                children: vec![server_script_service_id.clone()],
            },
        );

        instances.insert(
            server_script_service_id.clone(),
            AdapterNode {
                id: server_script_service_id.clone(),
                parent: Some(root_id.clone()),
                name: "ServerScriptService".to_string(),
                class_name: "ServerScriptService".to_string(),
                properties: Map::new(),
                children: vec![],
            },
        );

        let mut file_paths = HashMap::new();
        let root_exists = source_root.exists() && source_root.is_dir();
        if !root_exists {
            return Ok(ProjectSnapshot {
                root_id,
                instances,
                file_paths,
            });
        }

        for entry in WalkDir::new(&source_root).into_iter().filter_map(Result::ok) {
            let path = entry.path();
            if !entry.file_type().is_file() || !is_script_file(path) {
                continue;
            }

            let relative = match path.strip_prefix(&source_root) {
                Ok(value) => value,
                Err(_) => continue,
            };

            let parent_id = ensure_folder_chain(
                &mut instances,
                &server_script_service_id,
                relative.parent(),
            );
            let (name, class_name) = classify_file(path);
            let source = fs::read_to_string(path).unwrap_or_default();
            let instance_id = format!("ref_file_{}", sanitize_path_component(&relative.to_string_lossy()));

            let mut properties = Map::new();
            properties.insert("Source".to_string(), Value::String(source));

            let node = AdapterNode {
                id: instance_id.clone(),
                parent: Some(parent_id.clone()),
                name,
                class_name,
                properties,
                children: vec![],
            };

            instances.insert(instance_id.clone(), node);
            append_child(&mut instances, &parent_id, &instance_id);
            file_paths.insert(
                instance_id,
                path.canonicalize()
                    .unwrap_or_else(|_| path.to_path_buf())
                    .to_string_lossy()
                    .to_string(),
            );
        }

        Ok(ProjectSnapshot {
            root_id,
            instances,
            file_paths,
        })
    }

    fn resolve_rojo_project_file(&self, project_path: &str) -> Result<Option<PathBuf>> {
        let cwd = std::env::current_dir()?;
        let mut candidate = PathBuf::from(project_path);
        if !candidate.is_absolute() {
            candidate = cwd.join(candidate);
        }

        if candidate.is_file() && Project::is_project_file(&candidate) {
            return Ok(Some(candidate));
        }

        if candidate.is_dir() {
            for default_name in DEFAULT_PROJECT_NAMES {
                let maybe_file = candidate.join(default_name);
                if maybe_file.is_file() {
                    return Ok(Some(maybe_file));
                }
            }
        }

        Ok(None)
    }

    fn snapshot_from_rojo_project(&self, project_file_path: &Path) -> Result<Option<InstanceSnapshot>> {
        let vfs = Vfs::new_default();
        let emit_legacy_scripts = Project::load_fuzzy(&vfs, project_file_path)
            .ok()
            .flatten()
            .and_then(|project| project.emit_legacy_scripts);

        let context = InstanceContext::with_emit_legacy_scripts(emit_legacy_scripts);
        let snapshot = snapshot_from_vfs(&context, &vfs, project_file_path)?;
        Ok(snapshot)
    }

    fn project_snapshot_from_rojo_snapshot(&self, snapshot: InstanceSnapshot) -> ProjectSnapshot {
        let root_id = "ref_root".to_string();

        let mut instances = HashMap::new();
        let mut file_paths = HashMap::new();

        if snapshot.class_name == "DataModel" {
            let root_node = self.convert_rojo_node(
                &root_id,
                None,
                snapshot,
                &mut instances,
                &mut file_paths,
            );
            instances.insert(root_id.clone(), root_node);

            return ProjectSnapshot {
                root_id,
                instances,
                file_paths,
            };
        }

        let root_data_model_id = self.rojo_node_id(&snapshot, &root_id, 0);

        instances.insert(
            root_id.clone(),
            AdapterNode {
                id: root_id.clone(),
                parent: None,
                name: "Game".to_string(),
                class_name: "DataModel".to_string(),
                properties: Map::new(),
                children: vec![root_data_model_id.clone()],
            },
        );

        let root_node = self.convert_rojo_node(
            &root_data_model_id,
            Some(root_id.clone()),
            snapshot,
            &mut instances,
            &mut file_paths,
        );

        instances.insert(root_data_model_id, root_node);

        ProjectSnapshot {
            root_id,
            instances,
            file_paths,
        }
    }

    fn rojo_node_id(&self, snapshot: &InstanceSnapshot, parent_id: &str, index: usize) -> String {
        if let Some(path) = self.path_from_metadata(&snapshot.metadata) {
            return format!("ref_rojo_path_{}", sanitize_path_component(&path));
        }

        if let Some(specified_id) = snapshot.metadata.specified_id.as_ref() {
            return format!(
                "ref_rojo_spec_{}",
                sanitize_path_component(&specified_id.to_string())
            );
        }

        format!(
            "ref_rojo_{}_{}_{}_{}",
            sanitize_path_component(parent_id),
            sanitize_path_component(snapshot.name.as_ref()),
            sanitize_path_component(snapshot.class_name.as_ref()),
            index
        )
    }

    fn convert_rojo_node(
        &self,
        node_id: &str,
        parent: Option<String>,
        snapshot: InstanceSnapshot,
        instances: &mut HashMap<String, AdapterNode>,
        file_paths: &mut HashMap<String, String>,
    ) -> AdapterNode {
        let mut properties = Map::new();
        for (key, value) in &snapshot.properties {
            let prop_key = key.to_string();
            let json_value = serde_json::to_value(value)
                .unwrap_or_else(|_| Value::String(format!("{:?}", value)));
            properties.insert(prop_key, json_value);
        }

        if let Some(path) = self.path_from_metadata(&snapshot.metadata) {
            if properties.contains_key("Source") {
                file_paths.insert(node_id.to_string(), path);
            }
        }

        let mut children_ids = vec![];
        for (index, child) in snapshot.children.into_iter().enumerate() {
            let child_id = self.rojo_node_id(&child, node_id, index);
            let child_node = self.convert_rojo_node(
                &child_id,
                Some(node_id.to_string()),
                child,
                instances,
                file_paths,
            );
            instances.insert(child_id.clone(), child_node);
            children_ids.push(child_id);
        }

        AdapterNode {
            id: node_id.to_string(),
            parent,
            name: snapshot.name.to_string(),
            class_name: snapshot.class_name.to_string(),
            properties,
            children: children_ids,
        }
    }

    fn path_from_metadata(&self, metadata: &InstanceMetadata) -> Option<String> {
        if let Some(path) = metadata
            .relevant_paths
            .iter()
            .find(|value| is_script_file(value))
            .cloned()
        {
            return Some(canonical_path_string(&path));
        }

        if let Some(path) = metadata
            .instigating_source
            .as_ref()
            .map(|source| source.path().to_path_buf())
            .filter(|value| is_script_file(value))
        {
            return Some(canonical_path_string(&path));
        }

        metadata
            .relevant_paths
            .iter()
            .find(|value| is_script_file(value))
            .map(|path| canonical_path_string(path))
    }
}

fn is_script_file(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| ext.eq_ignore_ascii_case("lua") || ext.eq_ignore_ascii_case("luau"))
        .unwrap_or(false)
}

fn canonical_path_string(path: &Path) -> String {
    path.canonicalize()
        .unwrap_or_else(|_| path.to_path_buf())
        .to_string_lossy()
        .to_string()
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
    instances: &mut HashMap<String, AdapterNode>,
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
            let folder = AdapterNode {
                id: folder_id.clone(),
                parent: Some(parent_id.clone()),
                name,
                class_name: "Folder".to_string(),
                properties: Map::new(),
                children: vec![],
            };
            instances.insert(folder_id.clone(), folder);
            append_child(instances, &parent_id, &folder_id);
        }

        parent_id = folder_id;
    }

    parent_id
}

fn append_child(instances: &mut HashMap<String, AdapterNode>, parent_id: &str, child_id: &str) {
    if let Some(parent) = instances.get_mut(parent_id) {
        if !parent.children.iter().any(|existing| existing == child_id) {
            parent.children.push(child_id.to_string());
        }
    }
}

fn sanitize_path_component(value: &str) -> String {
    value
        .replace([':', '\\', '/', '.', '-', ' '], "_")
}

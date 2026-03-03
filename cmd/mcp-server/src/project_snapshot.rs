use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdapterNode {
    pub id: String,
    pub parent: Option<String>,
    pub name: String,
    #[serde(rename = "className")]
    pub class_name: String,
    #[serde(default)]
    pub properties: Map<String, Value>,
    #[serde(default)]
    pub children: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectSnapshot {
    #[serde(rename = "rootId")]
    pub root_id: String,
    #[serde(default)]
    pub instances: HashMap<String, AdapterNode>,
    #[serde(rename = "filePaths", default)]
    pub file_paths: HashMap<String, String>,
}

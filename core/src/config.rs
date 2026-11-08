use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

use crate::auth::LoginInfo;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Config {
    #[serde(default)]
    pub install_dir: String,
    #[serde(default)]
    pub launch_args: Vec<String>,
    #[serde(default)]
    pub last_server: String,
    #[serde(default)]
    pub login: Option<LoginInfo>,
}

pub fn config_dir() -> Option<PathBuf> {
    dirs::config_dir().map(|dir| dir.join("illusio"))
}

pub fn config_file() -> Option<PathBuf> {
    config_dir().map(|dir| dir.join("config.json"))
}

pub fn load_from(path: &PathBuf) -> Result<Config, String> {
    if !path.exists() {
        return Ok(Config::default());
    }
    let raw = fs::read_to_string(path).map_err(|error| error.to_string())?;
    serde_json::from_str(&raw).map_err(|error| error.to_string())
}

pub fn save_to(path: &PathBuf, config: &Config) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let raw = serde_json::to_string_pretty(config).map_err(|error| error.to_string())?;
    fs::write(path, raw).map_err(|error| error.to_string())
}

pub fn load() -> Result<Config, String> {
    match config_file() {
        Some(path) => load_from(&path),
        None => Err("каталог конфигурации не найден".into()),
    }
}

pub fn save(config: &Config) -> Result<(), String> {
    match config_file() {
        Some(path) => save_to(&path, config),
        None => Err("каталог конфигурации не найден".into()),
    }
}

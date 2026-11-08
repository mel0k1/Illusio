use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

use crate::auth::LoginInfo;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct FavoriteEntry {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub url: String,
    #[serde(default)]
    pub raised: i64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PrivacyAccept {
    #[serde(default)]
    pub identifier: String,
    #[serde(default)]
    pub version: String,
}

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
    #[serde(default)]
    pub favorites: Vec<FavoriteEntry>,
    #[serde(default)]
    pub accounts: Vec<LoginInfo>,
    #[serde(default)]
    pub theme: String,
    #[serde(default)]
    pub hide_empty: bool,
    #[serde(default)]
    pub hide_full: bool,
    #[serde(default)]
    pub fullscreen: bool,
    #[serde(default)]
    pub vsync: bool,
    #[serde(default)]
    pub mods_enabled: Vec<String>,
    #[serde(default)]
    pub hubs: Vec<String>,
    #[serde(default)]
    pub guest_username: String,
    #[serde(default)]
    pub username_override: String,
    #[serde(default)]
    pub engine_override: String,
    #[serde(default)]
    pub client_logs: bool,
    #[serde(default)]
    pub filter_tags: Vec<String>,
    #[serde(default)]
    pub filter_min_players: i64,
    #[serde(default)]
    pub filter_max_players: i64,
    #[serde(default)]
    pub accepted_privacy: Vec<PrivacyAccept>,
    #[serde(default = "default_language")]
    pub language: String,
    #[serde(default)]
    pub proxy_enabled: bool,
    #[serde(default)]
    pub proxy_host: String,
    #[serde(default)]
    pub proxy_port: i64,
    #[serde(default)]
    pub proxy_username: String,
    #[serde(default)]
    pub proxy_password: String,
    #[serde(default)]
    pub proxy_udp_relay: bool,
    #[serde(default)]
    pub proxy_apply_to_game: bool,
    #[serde(default)]
    pub dll_mods_enabled: Vec<String>,
}

fn default_language() -> String {
    "ru".to_string()
}

#[derive(Debug, Clone, Default)]
pub struct ProxyConfig {
    pub enabled: bool,
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: String,
    pub udp_relay: bool,
    pub apply_to_game: bool,
}

impl Config {
    pub fn proxy(&self) -> ProxyConfig {
        let port = self.proxy_port.clamp(0, 65535) as u16;
        ProxyConfig {
            enabled: self.proxy_enabled,
            host: self.proxy_host.trim().to_string(),
            port,
            username: self.proxy_username.clone(),
            password: self.proxy_password.clone(),
            udp_relay: self.proxy_udp_relay,
            apply_to_game: self.proxy_apply_to_game,
        }
    }
}

pub fn config_dir() -> Option<PathBuf> {
    dirs::config_dir().map(|dir| dir.join("illusio"))
}

pub fn config_file() -> Option<PathBuf> {
    config_dir().map(|dir| dir.join("config.json"))
}

pub fn mods_dir() -> Option<PathBuf> {
    config_dir().map(|dir| dir.join("mods"))
}

pub fn logs_dir() -> Option<PathBuf> {
    config_dir().map(|dir| dir.join("logs"))
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrips_new_fields() {
        let mut config = Config {
            hubs: vec!["https://hub.example.com/".into()],
            guest_username: "Гость".into(),
            username_override: "mel0k1".into(),
            engine_override: "/opt/engines/custom.zip".into(),
            client_logs: true,
            hide_full: true,
            filter_tags: vec!["lang:ru".into(), "18+".into()],
            filter_min_players: 2,
            filter_max_players: 90,
            accepted_privacy: vec![PrivacyAccept {
                identifier: "corvax".into(),
                version: "3".into(),
            }],
            favorites: vec![FavoriteEntry {
                name: "Wormix".into(),
                url: "ss14://wormix14.site".into(),
                raised: 42,
            }],
            ..Config::default()
        };
        config.proxy_enabled = true;
        config.proxy_host = "127.0.0.1".into();
        config.proxy_port = 1080;
        config.proxy_username = "user".into();
        config.proxy_password = "pass".into();
        config.proxy_udp_relay = true;
        config.proxy_apply_to_game = true;
        config.language = "en".into();
        config.dll_mods_enabled = vec!["half.dll".into()];
        let raw = serde_json::to_string(&config).unwrap();
        let parsed: Config = serde_json::from_str(&raw).unwrap();
        assert_eq!(parsed.hubs, config.hubs);
        assert!(parsed.proxy_enabled);
        assert_eq!(parsed.proxy().port, 1080);
        assert!(parsed.proxy().udp_relay);
        assert_eq!(parsed.language, "en");
        assert_eq!(parsed.dll_mods_enabled, vec!["half.dll".to_string()]);
        assert_eq!(parsed.guest_username, "Гость");
        assert_eq!(parsed.username_override, "mel0k1");
        assert!(parsed.client_logs);
        assert!(parsed.hide_full);
        assert_eq!(parsed.filter_tags, config.filter_tags);
        assert_eq!(parsed.filter_min_players, 2);
        assert_eq!(parsed.filter_max_players, 90);
        assert_eq!(parsed.accepted_privacy.len(), 1);
        assert_eq!(parsed.favorites[0].raised, 42);
    }

    #[test]
    fn reads_old_config() {
        let raw = r#"{"install_dir":"/opt/ss14","theme":"dark","favorites":[{"name":"A","url":"ss14://a.example"}]}"#;
        let parsed: Config = serde_json::from_str(raw).unwrap();
        assert_eq!(parsed.install_dir, "/opt/ss14");
        assert_eq!(parsed.favorites[0].raised, 0);
        assert!(parsed.hubs.is_empty());
        assert!(!parsed.client_logs);
        assert_eq!(parsed.language, "ru");
        assert!(!parsed.proxy_enabled);
        assert!(parsed.dll_mods_enabled.is_empty());
    }
}

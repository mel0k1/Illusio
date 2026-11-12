use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

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
pub struct ProxyProfile {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub host: String,
    #[serde(default)]
    pub port: i64,
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub password: String,
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
    pub proxy_updates: bool,
    #[serde(default)]
    pub proxy_region_bypass: bool,
    #[serde(default)]
    pub proxy_host: String,
    #[serde(default)]
    pub proxy_port: i64,
    #[serde(default)]
    pub proxy_username: String,
    #[serde(default)]
    pub proxy_password: String,
    #[serde(default)]
    pub proxy_profiles: Vec<ProxyProfile>,
    #[serde(default)]
    pub proxy_selected: String,
    #[serde(default)]
    pub proxy_udp_relay: bool,
    #[serde(default)]
    pub proxy_apply_to_game: bool,
    #[serde(default)]
    pub dll_mods_enabled: Vec<String>,
    #[serde(default)]
    pub subverter_enabled: Vec<String>,
    #[serde(default)]
    pub res_packs_enabled: Vec<String>,
    #[serde(default)]
    pub dump_resources: bool,
    #[serde(default = "default_blob_keep_days")]
    pub blob_keep_days: i64,
    #[serde(default = "default_bundle_keep")]
    pub bundle_keep: i64,
    #[serde(default = "default_engine_keep")]
    pub engine_keep: i64,
    #[serde(default)]
    pub auto_update: bool,
    #[serde(default)]
    pub prefetch_favorites: bool,
    #[serde(default)]
    pub patch_hwid: bool,
    #[serde(default)]
    pub patch_rpc: bool,
    #[serde(default)]
    pub patch_jam_dials: bool,
    #[serde(default)]
    pub patch_blackhole: bool,
    #[serde(default)]
    pub skip_privacy: bool,
    #[serde(default)]
    pub throw_patch_fail: bool,
    #[serde(default)]
    pub no_autologin: bool,
    #[serde(default)]
    pub patch_flyi: bool,
    #[serde(default)]
    pub ps_debug: bool,
    #[serde(default = "default_hide_level")]
    pub hide_level: i64,
    #[serde(default)]
    pub hwid_mode: String,
    #[serde(default)]
    pub hwid_value: String,
    #[serde(default)]
    pub hwid_optout: bool,
    #[serde(default = "default_true")]
    pub dynamic_pgo: bool,
    #[serde(default = "default_true")]
    pub backports: bool,
    #[serde(default)]
    pub backports_no_any: bool,
    #[serde(default)]
    pub rpc_fake: bool,
    #[serde(default = "default_rpc_fake_name")]
    pub rpc_fake_name: String,
    #[serde(default = "default_true")]
    pub proxy_guard_launch: bool,
    #[serde(default = "default_dock_side")]
    pub dock_side: String,
    #[serde(default = "default_corners")]
    pub corners: String,
    #[serde(default = "default_font")]
    pub font: String,
    #[serde(default)]
    pub custom_color: i64,
    #[serde(default)]
    pub patchless: bool,
    #[serde(default)]
    pub stealth_registries: bool,
    #[serde(default)]
    pub admin_guid: bool,
    #[serde(default)]
    pub admin_guid_value: String,
    #[serde(default)]
    pub mod_logs: bool,
    #[serde(default)]
    pub filter_hubs: Vec<String>,
    #[serde(default)]
    pub update_prerelease: bool,
    #[serde(default = "default_true")]
    pub card_map: bool,
    #[serde(default = "default_true")]
    pub card_preset: bool,
    #[serde(default = "default_true")]
    pub card_round: bool,
    #[serde(default)]
    pub avatar_path: String,
}

fn default_dock_side() -> String {
    "bottom".to_string()
}

fn default_corners() -> String {
    "normal".to_string()
}

fn default_font() -> String {
    "default".to_string()
}

fn default_hide_level() -> i64 {
    2
}

fn default_true() -> bool {
    true
}

fn default_rpc_fake_name() -> String {
    "Illusio".to_string()
}

fn default_blob_keep_days() -> i64 {
    7
}

fn default_bundle_keep() -> i64 {
    10
}

fn default_engine_keep() -> i64 {
    2
}

fn default_language() -> String {
    "ru".to_string()
}

#[derive(Debug, Clone, Default)]
pub struct ProxyConfig {
    pub launcher: bool,
    pub updates: bool,
    pub region: bool,
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: String,
    pub udp_relay: bool,
    pub apply_to_game: bool,
}

impl ProxyConfig {
    pub fn configured(&self) -> bool {
        (self.launcher || self.updates || self.region || self.udp_relay || self.apply_to_game)
            && !self.host.trim().is_empty()
            && self.port > 0
    }

    pub fn any_route(&self) -> bool {
        self.launcher || self.updates || self.region
    }
}

impl Config {
    pub fn migrated(mut self) -> Config {
        if self.proxy_profiles.is_empty() && !self.proxy_host.trim().is_empty() {
            self.proxy_profiles.push(ProxyProfile {
                id: "default".into(),
                name: "Default".into(),
                host: self.proxy_host.clone(),
                port: self.proxy_port,
                username: self.proxy_username.clone(),
                password: self.proxy_password.clone(),
            });
            if self.proxy_selected.trim().is_empty() {
                self.proxy_selected = "default".into();
            }
        }
        self
    }

    pub fn proxy_profile(&self) -> Option<&ProxyProfile> {
        let id = self.proxy_selected.trim();
        self.proxy_profiles
            .iter()
            .find(|profile| profile.id == id)
            .or_else(|| self.proxy_profiles.first())
    }

    pub fn proxy(&self) -> ProxyConfig {
        let profile = self.proxy_profile();
        ProxyConfig {
            launcher: self.proxy_enabled,
            updates: self.proxy_updates,
            region: self.proxy_region_bypass,
            host: profile
                .map(|value| value.host.trim().to_string())
                .unwrap_or_default(),
            port: profile
                .map(|value| value.port.clamp(0, 65535) as u16)
                .unwrap_or(0),
            username: profile
                .map(|value| value.username.clone())
                .unwrap_or_default(),
            password: profile
                .map(|value| value.password.clone())
                .unwrap_or_default(),
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

pub fn res_packs_dir() -> Option<PathBuf> {
    config_dir().map(|dir| dir.join("respacks"))
}

pub fn dumps_dir() -> Option<PathBuf> {
    config_dir().map(|dir| dir.join("dumps"))
}

pub fn logs_dir() -> Option<PathBuf> {
    config_dir().map(|dir| dir.join("logs"))
}

pub fn load_from(path: &PathBuf) -> Result<Config, String> {
    if !path.exists() {
        return Ok(Config::default());
    }
    let raw = fs::read_to_string(path).map_err(|error| error.to_string())?;
    match serde_json::from_str::<Config>(&raw) {
        Ok(config) => Ok(config.migrated()),
        Err(error) => {
            let backup = path.with_extension("json.bak");
            if let Ok(previous) = fs::read_to_string(&backup) {
                if let Ok(config) = serde_json::from_str::<Config>(&previous) {
                    return Ok(config.migrated());
                }
            }
            Err(error.to_string())
        }
    }
}

static SAVE_COUNTER: AtomicU64 = AtomicU64::new(0);

pub fn save_to(path: &PathBuf, config: &Config) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let raw = serde_json::to_string_pretty(config).map_err(|error| error.to_string())?;
    let backup = path.with_extension("json.bak");
    if path.exists() {
        if let Err(error) = fs::copy(path, &backup) {
            eprintln!("illusio: не удалось создать резервную копию конфигурации: {error}");
        }
    }
    let sequence = SAVE_COUNTER.fetch_add(1, Ordering::Relaxed);
    let file_name = path
        .file_name()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_else(|| "config.json".into());
    let temp = path.with_file_name(format!(
        "{file_name}.tmp.{}.{}",
        std::process::id(),
        sequence
    ));
    let result = (|| -> Result<(), String> {
        let mut file = fs::File::create(&temp).map_err(|error| error.to_string())?;
        file.write_all(raw.as_bytes())
            .map_err(|error| error.to_string())?;
        file.sync_all().map_err(|error| error.to_string())?;
        Ok(())
    })();
    if let Err(message) = result {
        fs::remove_file(&temp).ok();
        return Err(message);
    }
    if let Err(error) = fs::rename(&temp, path) {
        fs::remove_file(&temp).ok();
        return Err(error.to_string());
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o600));
    }
    Ok(())
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
        config.proxy_updates = true;
        config.proxy_profiles.push(ProxyProfile {
            id: "main".into(),
            name: "Main".into(),
            host: "127.0.0.1".into(),
            port: 1080,
            username: "user".into(),
            password: "pass".into(),
        });
        config.proxy_selected = "main".into();
        config.proxy_udp_relay = true;
        config.proxy_apply_to_game = true;
        config.language = "en".into();
        config.dll_mods_enabled = vec!["half.dll".into()];
        config.skip_privacy = true;
        config.throw_patch_fail = true;
        config.no_autologin = true;
        config.patch_flyi = true;
        config.ps_debug = true;
        config.subverter_enabled = vec!["/mods/subverter.dll".into()];
        config.res_packs_enabled = vec!["HiTech".into()];
        config.dump_resources = true;
        let raw = serde_json::to_string(&config).unwrap();
        let parsed: Config = serde_json::from_str(&raw).unwrap();
        assert_eq!(parsed.hubs, config.hubs);
        assert!(parsed.proxy_enabled);
        assert!(parsed.proxy_updates);
        assert_eq!(parsed.proxy().port, 1080);
        assert_eq!(parsed.proxy().username, "user");
        assert!(parsed.proxy().udp_relay);
        assert!(parsed.proxy().configured());
        assert_eq!(parsed.language, "en");
        assert!(parsed.skip_privacy);
        assert!(parsed.throw_patch_fail);
        assert!(parsed.no_autologin);
        assert!(parsed.patch_flyi);
        assert!(parsed.ps_debug);
        assert_eq!(parsed.dll_mods_enabled, vec!["half.dll".to_string()]);
        assert_eq!(
            parsed.subverter_enabled,
            vec!["/mods/subverter.dll".to_string()]
        );
        assert_eq!(parsed.res_packs_enabled, vec!["HiTech".to_string()]);
        assert!(parsed.dump_resources);
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
        assert!(parsed.subverter_enabled.is_empty());
        assert!(parsed.res_packs_enabled.is_empty());
        assert!(!parsed.dump_resources);
    }

    #[test]
    fn migrates_legacy_proxy() {
        let raw = r#"{"proxy_enabled":true,"proxy_host":"10.0.0.8","proxy_port":1081,"proxy_username":"u","proxy_password":"p","proxy_udp_relay":true}"#;
        let parsed: Config = serde_json::from_str::<Config>(raw).unwrap().migrated();
        assert_eq!(parsed.proxy_profiles.len(), 1);
        assert_eq!(parsed.proxy_selected, "default");
        let proxy = parsed.proxy();
        assert_eq!(proxy.host, "10.0.0.8");
        assert_eq!(proxy.port, 1081);
        assert_eq!(proxy.username, "u");
        assert!(proxy.launcher);
        assert!(proxy.udp_relay);
        assert!(proxy.configured());
        assert!(proxy.any_route());
    }

    #[test]
    fn falls_back_to_first_profile() {
        let mut config = Config::default();
        config.proxy_profiles.push(ProxyProfile {
            id: "a".into(),
            name: "A".into(),
            host: "1.1.1.1".into(),
            port: 1080,
            ..ProxyProfile::default()
        });
        assert_eq!(config.proxy().host, "1.1.1.1");
        config.proxy_selected = "missing".into();
        assert_eq!(config.proxy().host, "1.1.1.1");
    }

    #[test]
    fn keeps_look_and_new_fields() {
        let raw = r#"{
            "dock_side": "left",
            "corners": "round",
            "font": "manrope",
            "custom_color": 65280,
            "patchless": true,
            "stealth_registries": true,
            "admin_guid": true,
            "admin_guid_value": "0123456789abcdef0123456789abcdef",
            "mod_logs": true,
            "filter_hubs": ["https://hub.example.com/"],
            "update_prerelease": true,
            "card_map": false,
            "card_preset": false,
            "card_round": false
        }"#;
        let parsed: Config = serde_json::from_str(raw).unwrap();
        assert_eq!(parsed.dock_side, "left");
        assert_eq!(parsed.corners, "round");
        assert_eq!(parsed.font, "manrope");
        assert_eq!(parsed.custom_color, 65280);
        assert!(parsed.patchless);
        assert!(parsed.stealth_registries);
        assert!(parsed.admin_guid);
        assert_eq!(parsed.admin_guid_value, "0123456789abcdef0123456789abcdef");
        assert!(parsed.mod_logs);
        assert_eq!(parsed.filter_hubs, vec!["https://hub.example.com/"]);
        assert!(parsed.update_prerelease);
        assert!(!parsed.card_map);
        assert!(!parsed.card_preset);
        assert!(!parsed.card_round);
        let round = serde_json::to_string(&parsed).unwrap();
        let reparsed: Config = serde_json::from_str(&round).unwrap();
        assert_eq!(reparsed.dock_side, "left");
        assert_eq!(reparsed.custom_color, 65280);
        assert!(reparsed.patchless);
        assert_eq!(reparsed.filter_hubs.len(), 1);
        let empty: Config = serde_json::from_str("{}").unwrap();
        assert_eq!(empty.dock_side, "bottom");
        assert_eq!(empty.corners, "normal");
        assert_eq!(empty.font, "default");
        assert!(empty.card_map);
        assert!(empty.card_preset);
        assert!(empty.card_round);
    }
}

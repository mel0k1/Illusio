use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crate::config::ProxyConfig;
use crate::socks::{parse_udp_address, prepare_udp_relay, PreparedRelay};

const CRASH_WINDOW: Duration = Duration::from_millis(300);

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct LaunchSpec {
    #[serde(default)]
    pub install_dir: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub server_url: String,
    #[serde(default)]
    pub connect_address: String,
    #[serde(default)]
    pub auth_token: String,
    #[serde(default)]
    pub auth_user_id: String,
    #[serde(default)]
    pub auth_pubkey: String,
    #[serde(default)]
    pub auth_server: String,
    #[serde(default)]
    pub build_download_url: String,
    #[serde(default)]
    pub build_version: String,
    #[serde(default)]
    pub build_fork_id: String,
    #[serde(default)]
    pub build_hash: String,
    #[serde(default)]
    pub build_engine_version: String,
    #[serde(default)]
    pub build_manifest_url: String,
    #[serde(default)]
    pub build_manifest_download_url: String,
    #[serde(default)]
    pub build_manifest_hash: String,
    #[serde(default)]
    pub mode: String,
    #[serde(default)]
    pub loader_dir: String,
    #[serde(default)]
    pub engine_zip: String,
    #[serde(default)]
    pub content_zip: String,
    #[serde(default)]
    pub engine_sig: String,
    #[serde(default)]
    pub mods: Vec<String>,
    #[serde(default)]
    pub mod_dlls: Vec<String>,
    #[serde(default)]
    pub subverters: Vec<String>,
    #[serde(default)]
    pub res_packs: Vec<String>,
    #[serde(default, rename = "dump_resources")]
    pub dump_resources: bool,
    #[serde(default, rename = "log_dir")]
    pub log_dir: String,
    #[serde(default, rename = "allow_unsigned")]
    pub allow_unsigned: bool,
    #[serde(default, rename = "patch_hwid")]
    pub patch_hwid: bool,
    #[serde(default, rename = "patch_rpc")]
    pub patch_rpc: bool,
    #[serde(default, rename = "patch_jam_dials")]
    pub patch_jam_dials: bool,
    #[serde(default, rename = "patch_blackhole")]
    pub patch_blackhole: bool,
    #[serde(default = "default_hide_level")]
    pub hide_level: i64,
    #[serde(default, rename = "hwid_mode")]
    pub hwid_mode: String,
    #[serde(default, rename = "hwid_value")]
    pub hwid_value: String,
    #[serde(default, rename = "hwid_optout")]
    pub hwid_optout: bool,
    #[serde(default = "default_true")]
    pub dynamic_pgo: bool,
    #[serde(default, rename = "backports")]
    pub backports: bool,
    #[serde(default, rename = "backports_no_any")]
    pub backports_no_any: bool,
    #[serde(default, rename = "rpc_fake")]
    pub rpc_fake: bool,
    #[serde(default, rename = "rpc_fake_name")]
    pub rpc_fake_name: String,
    #[serde(default, rename = "patchless")]
    pub patchless: bool,
    #[serde(default, rename = "stealth_registries")]
    pub stealth_registries: bool,
    #[serde(default, rename = "admin_guid")]
    pub admin_guid: bool,
    #[serde(default, rename = "admin_guid_value")]
    pub admin_guid_value: String,
    #[serde(default, rename = "mod_logs")]
    pub mod_logs: bool,
    #[serde(default, rename = "modules")]
    pub modules: Vec<String>,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct LaunchStatus {
    pub pid: u32,
    pub running: bool,
    pub exited: bool,
    pub crashed: bool,
    pub exit_code: i64,
    #[serde(rename = "logTail")]
    pub log_tail: String,
    #[serde(rename = "launchedAt")]
    pub launched_at: i64,
}

static LAST_LAUNCH: OnceLock<Mutex<Option<LaunchStatus>>> = OnceLock::new();

fn record_launch(patch: impl FnOnce(&mut LaunchStatus)) {
    let cell = LAST_LAUNCH.get_or_init(|| Mutex::new(None));
    if let Ok(mut guard) = cell.lock() {
        let status = guard.get_or_insert_with(LaunchStatus::default);
        patch(status);
    }
}

pub fn status_snapshot() -> LaunchStatus {
    match LAST_LAUNCH.get().and_then(|cell| cell.lock().ok()) {
        Some(guard) => guard.clone().unwrap_or_default(),
        None => LaunchStatus::default(),
    }
}

fn unix_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_millis() as i64)
        .unwrap_or(0)
}

fn log_tail(log_dir: &str, limit: usize) -> String {
    let dir = PathBuf::from(log_dir.trim());
    if dir.as_os_str().is_empty() {
        return String::new();
    }
    let mut parts: Vec<String> = Vec::new();
    for name in ["client.stderr.log", "client.stdout.log"] {
        let path = dir.join(name);
        let Ok(data) = fs::read(&path) else {
            continue;
        };
        let start = data.len().saturating_sub(limit);
        let text = String::from_utf8_lossy(&data[start..]);
        let text = text.trim();
        if !text.is_empty() {
            parts.push(text.to_string());
        }
    }
    parts.join("\n")
}

fn watch_child(mut child: std::process::Child, log_dir: String, relay: Option<PreparedRelay>) {
    std::thread::spawn(move || {
        let pid = child.id();
        let started = Instant::now();
        record_launch(|status| {
            status.pid = pid;
            status.running = true;
            status.crashed = false;
            status.launched_at = unix_millis();
        });
        let deadline = started + CRASH_WINDOW;
        loop {
            match child.try_wait() {
                Ok(Some(status)) => {
                    let quick = started.elapsed() <= CRASH_WINDOW;
                    let tail = log_tail(&log_dir, 4096);
                    record_launch(|entry| {
                        entry.running = false;
                        entry.exited = true;
                        entry.crashed = quick;
                        entry.exit_code = status.code().unwrap_or(-1) as i64;
                        entry.log_tail = tail;
                    });
                    if let Some(relay) = relay {
                        relay.stop();
                    }
                    break;
                }
                Ok(None) => {
                    if Instant::now() >= deadline {
                        if let Some(relay) = relay {
                            relay.start(child);
                        }
                        break;
                    }
                    std::thread::sleep(Duration::from_millis(25));
                }
                Err(_) => {
                    if let Some(relay) = relay {
                        relay.stop();
                    }
                    break;
                }
            }
        }
    });
}

fn default_hide_level() -> i64 {
    2
}

fn default_true() -> bool {
    true
}

pub fn client_path(install_dir: &str) -> PathBuf {
    let dir = PathBuf::from(install_dir);
    if cfg!(windows) {
        dir.join("Robust.Client.exe")
    } else {
        dir.join("Robust.Client")
    }
}

pub fn derive_connect_address(server_url: &str, info_address: &str) -> String {
    let trimmed = info_address.trim();
    if !trimmed.is_empty() {
        return trimmed.to_string();
    }
    let raw = server_url.trim().trim_end_matches('/');
    if raw.is_empty() {
        return String::new();
    }
    let scheme_part = raw.split_once("://").map(|(_, rest)| rest).unwrap_or(raw);
    let authority = scheme_part.split(['/', '?']).next().unwrap_or("");
    if authority.is_empty() {
        return String::new();
    }
    if authority.contains(':') {
        format!("udp://{authority}")
    } else {
        format!("udp://{authority}:1212")
    }
}

pub fn build_args(spec: &LaunchSpec) -> Vec<String> {
    let mut args = Vec::new();
    let username = spec.username.trim();
    if !username.is_empty() {
        args.push("--username".into());
        args.push(username.to_string());
    }
    args.push("--cvar".into());
    args.push("launch.launcher=true".into());
    let connect = derive_connect_address(&spec.server_url, &spec.connect_address);
    if !connect.is_empty() {
        args.push("--launcher".into());
        args.push("--connect-address".into());
        args.push(connect);
    }
    let mut cvar = |name: &str, value: &str| {
        let value = value.trim();
        if value.is_empty() {
            return;
        }
        args.push("--cvar".into());
        args.push(format!("build.{name}={value}"));
    };
    cvar("download_url", &spec.build_download_url);
    cvar("version", &spec.build_version);
    cvar("fork_id", &spec.build_fork_id);
    cvar("hash", &spec.build_hash);
    cvar("engine_version", &spec.build_engine_version);
    cvar("manifest_url", &spec.build_manifest_url);
    cvar("manifest_download_url", &spec.build_manifest_download_url);
    cvar("manifest_hash", &spec.build_manifest_hash);
    args.extend(spec.args.iter().cloned());
    args
}

fn clean_list(values: &[String]) -> Vec<String> {
    values
        .iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect()
}

pub fn build_env(spec: &LaunchSpec) -> Vec<(String, String)> {
    let mut env = Vec::new();
    let token = spec.auth_token.trim();
    if token.is_empty() {
        return env;
    }
    env.push(("ROBUST_AUTH_TOKEN".into(), token.to_string()));
    let mut user_id = spec.auth_user_id.trim().to_string();
    if spec.admin_guid {
        if let Some(guid) = normalize_guid(&spec.admin_guid_value) {
            user_id = guid;
        }
    }
    if !user_id.is_empty() {
        env.push(("ROBUST_AUTH_USERID".into(), user_id));
    }
    let pubkey = spec.auth_pubkey.trim();
    if !pubkey.is_empty() {
        env.push(("ROBUST_AUTH_PUBKEY".into(), pubkey.to_string()));
    }
    let server = spec.auth_server.trim();
    if !server.is_empty() {
        env.push(("ROBUST_AUTH_SERVER".into(), server.to_string()));
    }
    let mods = clean_list(&spec.mods);
    if !mods.is_empty() {
        env.push(("SS14_LOADER_OVERLAY_ZIPS".into(), mods.join(";")));
    }
    let dlls = clean_list(&spec.mod_dlls);
    if !dlls.is_empty() {
        env.push(("SS14_LOADER_MOD_DLLS".into(), dlls.join(";")));
    }
    let subverters = clean_list(&spec.subverters);
    if !subverters.is_empty() {
        env.push(("SS14_LOADER_SUBVERTERS".into(), subverters.join(";")));
    }
    let packs = clean_list(&spec.res_packs);
    if !packs.is_empty() {
        env.push(("SS14_LOADER_RES_PACKS".into(), packs.join(";")));
    }
    if spec.dump_resources {
        env.push(("ILLUSIO_DUMP".into(), "1".into()));
        let fork = sanitize_fork_id(&spec.build_fork_id);
        if let Some(dir) = crate::config::dumps_dir() {
            env.push((
                "SS14_LOADER_DUMP_DIR".into(),
                dir.join(fork).display().to_string(),
            ));
        }
    }
    if spec.patch_hwid {
        env.push(("ILLUSIO_PATCH_HWID".into(), "1".into()));
    }
    if spec.patch_rpc {
        env.push(("ILLUSIO_PATCH_RPC".into(), "1".into()));
    }
    if spec.patch_jam_dials {
        env.push(("ILLUSIO_PATCH_JAM_DIALS".into(), "1".into()));
    }
    if spec.patch_blackhole {
        env.push(("ILLUSIO_PATCH_BLACKHOLE".into(), "1".into()));
    }
    env.push((
        "ILLUSIO_HIDE_LEVEL".into(),
        spec.hide_level.clamp(0, 4).to_string(),
    ));
    let mut hwid_mode = spec.hwid_mode.trim().to_ascii_lowercase();
    if hwid_mode.is_empty() && spec.patch_hwid {
        hwid_mode = "random".into();
    }
    match hwid_mode.as_str() {
        "random" => {
            env.push(("ILLUSIO_HWID_MODE".into(), "random".into()));
        }
        "fixed" | "account" => {
            if let Some(value) = normalize_hwid(&spec.hwid_value) {
                env.push(("ILLUSIO_HWID_MODE".into(), "fixed".into()));
                env.push(("ILLUSIO_HWID_VALUE".into(), value));
            } else {
                env.push(("ILLUSIO_HWID_MODE".into(), "random".into()));
            }
        }
        _ => {}
    }
    if spec.hwid_optout {
        env.push(("ROBUST_AUTH_ALLOW_HWID".into(), "0".into()));
    }
    if spec.dynamic_pgo {
        for (key, value) in [
            ("DOTNET_TieredPGO", "1"),
            ("DOTNET_TC_QuickJitForLoops", "1"),
            ("DOTNET_ReadyToRun", "0"),
            ("DOTNET_gcServer", "1"),
            ("DOTNET_TieredCompilationMinCallCount", "0"),
        ] {
            env.push((key.into(), value.into()));
        }
    }
    if spec.backports {
        env.push(("ILLUSIO_BACKPORTS".into(), "1".into()));
        if spec.backports_no_any {
            env.push(("ILLUSIO_NO_ANY_BACKPORTS".into(), "1".into()));
        }
    }
    let fork = sanitize_fork_id(&spec.build_fork_id);
    if !fork.is_empty() {
        env.push(("ILLUSIO_FORK_ID".into(), fork));
    }
    let engine_version = spec.build_engine_version.trim();
    if !engine_version.is_empty() {
        env.push(("ILLUSIO_ENGINE_VER".into(), engine_version.to_string()));
    }
    if spec.rpc_fake {
        env.push(("ILLUSIO_RPC_FAKE".into(), "1".into()));
        let fake = spec.rpc_fake_name.trim();
        if !fake.is_empty() {
            env.push(("ILLUSIO_RPC_USERNAME".into(), fake.to_string()));
        }
    }
    if spec.patchless {
        env.push(("ILLUSIO_PATCHLESS".into(), "1".into()));
    }
    if spec.stealth_registries {
        env.push(("ILLUSIO_STEALTH_REGISTRIES".into(), "1".into()));
    }
    if spec.mod_logs {
        env.push(("ILLUSIO_MOD_LOGS".into(), "1".into()));
        if let Some(dir) = crate::config::logs_dir() {
            env.push(("ILLUSIO_LOGS_DIR".into(), dir.display().to_string()));
        }
    }
    let modules = clean_list(&spec.modules);
    for pair in crate::modules::env_pairs(&modules) {
        env.push(pair);
    }
    env
}

pub fn normalize_guid(raw: &str) -> Option<String> {
    let value = raw.trim().trim_matches(['{', '}']).to_ascii_lowercase();
    if value.len() != 32 || !value.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    Some(value)
}

pub fn normalize_hwid(raw: &str) -> Option<String> {
    let value = raw.trim().trim_start_matches("0x").to_ascii_lowercase();
    if value.is_empty() || !value.len().is_multiple_of(2) || value.len() > 128 {
        return None;
    }
    if !value.chars().all(|character| character.is_ascii_hexdigit()) {
        return None;
    }
    Some(value)
}

pub fn stealth_fuse(hide_level: i64, engine_version: &str) -> Result<(), String> {
    if hide_level > 0 {
        return Ok(());
    }
    let major = engine_version
        .trim()
        .split('.')
        .next()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(0);
    if major >= 183 {
        return Err(
            "скрытие патчей выключено, а движок этой сборки может раскрывать моды; включите скрытие патчей в настройках"
                .into(),
        );
    }
    Ok(())
}

fn sanitize_fork_id(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return "unknown".to_string();
    }
    let safe: String = trimmed
        .chars()
        .map(|value| {
            if value.is_ascii_alphanumeric() || value == '-' || value == '_' {
                value
            } else {
                '_'
            }
        })
        .collect();
    if safe.is_empty() {
        "unknown".to_string()
    } else {
        safe
    }
}

fn apply_proxy_env(command: &mut Command, proxy: &ProxyConfig) {
    if !proxy.apply_to_game {
        return;
    }
    if let Some(url) = crate::socks::proxy_url(proxy) {
        for key in ["ALL_PROXY", "HTTP_PROXY", "HTTPS_PROXY"] {
            command.env(key, &url);
        }
        command.env("NO_PROXY", "localhost,127.0.0.1");
    }
}

fn prepare_relay(proxy: &ProxyConfig, args: &mut [String]) -> Option<PreparedRelay> {
    if !proxy.udp_relay {
        return None;
    }
    let index = args.iter().position(|value| value == "--connect-address")?;
    let address = args.get(index + 1)?.clone();
    let (host, port) = parse_udp_address(&address)?;
    match prepare_udp_relay(proxy, &host, port) {
        Ok(relay) => {
            args[index + 1] = format!("udp://127.0.0.1:{}", relay.local_port);
            Some(relay)
        }
        Err(_) => None,
    }
}

pub fn loader_path(loader_dir: &str) -> PathBuf {
    let dir = PathBuf::from(loader_dir);
    if cfg!(windows) {
        dir.join("illusio-loader.exe")
    } else {
        dir.join("illusio-loader")
    }
}

fn open_logs(log_dir: &str, name: &str) -> Option<fs::File> {
    let dir = PathBuf::from(log_dir.trim());
    if dir.as_os_str().is_empty() {
        return None;
    }
    fs::create_dir_all(&dir).ok()?;
    fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(dir.join(name))
        .ok()
}

fn apply_streams(command: &mut Command, log_dir: &str) {
    let stdout = open_logs(log_dir, "client.stdout.log");
    let stderr = open_logs(log_dir, "client.stderr.log");
    if let Some(file) = stdout {
        command.stdout(Stdio::from(file));
    } else {
        command.stdout(Stdio::null());
    }
    if let Some(file) = stderr {
        command.stderr(Stdio::from(file));
    } else {
        command.stderr(Stdio::null());
    }
}

pub fn launch(spec: &LaunchSpec) -> Result<u32, String> {
    stealth_fuse(spec.hide_level, &spec.build_engine_version)?;
    let config = crate::config::load().unwrap_or_default();
    let proxy = config.proxy();
    if spec.mode.trim().eq_ignore_ascii_case("acz") {
        return launch_loader(spec, &proxy);
    }
    let path = client_path(&spec.install_dir);
    if !path.exists() {
        return Err(format!("клиент не найден: {}", path.display()));
    }
    let mut args = build_args(spec);
    let relay = prepare_relay(&proxy, &mut args);
    let mut command = Command::new(&path);
    command.args(&args);
    apply_streams(&mut command, &spec.log_dir);
    for (key, value) in build_env(spec) {
        command.env(key, value);
    }
    apply_proxy_env(&mut command, &proxy);
    let child = command
        .spawn()
        .map_err(|error| format!("не удалось запустить клиент: {error}"))?;
    let pid = child.id();
    watch_child(child, spec.log_dir.clone(), relay);
    Ok(pid)
}

fn launch_loader(spec: &LaunchSpec, proxy: &ProxyConfig) -> Result<u32, String> {
    let loader = loader_path(&spec.loader_dir);
    if !loader.exists() {
        return Err(
            "loader не найден: он входит в готовые сборки Illusio из раздела Releases".into(),
        );
    }
    let engine_zip = PathBuf::from(&spec.engine_zip);
    if !engine_zip.exists() {
        return Err("архив движка не найден, повторите подключение".into());
    }
    let content_zip = PathBuf::from(&spec.content_zip);
    if !content_zip.exists() {
        return Err("файлы сборки не найдены, повторите подключение".into());
    }
    let pubkey = PathBuf::from(&spec.loader_dir).join("signing_key");
    if !pubkey.exists() {
        return Err("ключ подписи движков не найден рядом с loader".into());
    }
    let sig = spec.engine_sig.trim();
    if sig.is_empty() {
        return Err("у сборки движка нет подписи".into());
    }
    let mut args = build_args(spec);
    let relay = prepare_relay(proxy, &mut args);
    let mut command = Command::new(&loader);
    command.arg(&engine_zip).arg(sig).arg(&pubkey).args(&args);
    apply_streams(&mut command, &spec.log_dir);
    command.env("SS14_LOADER_OVERLAY_ZIP", &content_zip);
    if spec.allow_unsigned {
        command.env("SS14_DISABLE_SIGNING", "true");
    }
    for (key, value) in build_env(spec) {
        command.env(key, value);
    }
    apply_proxy_env(&mut command, proxy);
    let child = command
        .spawn()
        .map_err(|error| format!("не удалось запустить клиент: {error}"))?;
    let pid = child.id();
    watch_child(child, spec.log_dir.clone(), relay);
    Ok(pid)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec() -> LaunchSpec {
        LaunchSpec {
            install_dir: "/opt/ss14".into(),
            username: "mel0k1".into(),
            server_url: "ss14://game.example.com:1212/".into(),
            connect_address: "udp://game.example.com:1212".into(),
            auth_token: "tok".into(),
            auth_user_id: "uid".into(),
            auth_pubkey: "key".into(),
            auth_server: "https://auth.spacestation14.com/".into(),
            build_version: "240.1".into(),
            build_fork_id: "space_wizards".into(),
            build_hash: "deadbeef".into(),
            ..LaunchSpec::default()
        }
    }

    #[test]
    fn derives_connect_address() {
        assert_eq!(
            derive_connect_address("ss14://game.example.com", ""),
            "udp://game.example.com:1212"
        );
        assert_eq!(
            derive_connect_address("udp://game.example.com:1212", ""),
            "udp://game.example.com:1212"
        );
        assert_eq!(
            derive_connect_address("ss14://game.example.com", "udp://real.example.com:4002"),
            "udp://real.example.com:4002"
        );
        assert_eq!(derive_connect_address("", ""), "");
    }

    #[test]
    fn composes_launch_args() {
        let args = build_args(&spec());
        let position = args
            .windows(2)
            .position(|pair| pair == ["--username", "mel0k1"])
            .expect("username present");
        assert!(position == 0);
        assert!(args.contains(&"--launcher".to_string()));
        let index = args
            .iter()
            .position(|value| value == "--connect-address")
            .expect("connect address present");
        assert_eq!(args[index + 1], "udp://game.example.com:1212");
        assert!(args.contains(&"build.hash=deadbeef".to_string()));
        assert!(args.contains(&"launch.launcher=true".to_string()));
    }

    #[test]
    fn skips_empty_build_values() {
        let mut spec = spec();
        spec.build_hash = String::new();
        spec.build_manifest_url = String::new();
        spec.server_url = String::new();
        spec.connect_address = String::new();
        spec.username = String::new();
        let args = build_args(&spec);
        assert!(!args.iter().any(|value| value.contains("build.hash")));
        assert!(!args.contains(&"--launcher".to_string()));
        assert!(!args.contains(&"--username".to_string()));
    }

    #[test]
    fn env_requires_token() {
        let empty = build_env(&LaunchSpec::default());
        assert!(empty.is_empty());
        let env = build_env(&spec());
        assert!(env.contains(&("ROBUST_AUTH_TOKEN".into(), "tok".into())));
        assert!(env.contains(&("ROBUST_AUTH_USERID".into(), "uid".into())));
        assert!(env.contains(&("ROBUST_AUTH_PUBKEY".into(), "key".into())));
        assert!(env.contains(&(
            "ROBUST_AUTH_SERVER".into(),
            "https://auth.spacestation14.com/".into()
        )));
    }

    #[test]
    fn env_carries_dll_mods() {
        let spec = LaunchSpec {
            auth_token: "tok".into(),
            mod_dlls: vec!["/mods/a.dll".into(), " ".into(), "/mods/b.dll".into()],
            ..LaunchSpec::default()
        };
        let env = build_env(&spec);
        assert!(env.contains(&(
            "SS14_LOADER_MOD_DLLS".into(),
            "/mods/a.dll;/mods/b.dll".into()
        )));
    }

    #[test]
    fn env_carries_subverters_and_packs() {
        let spec = LaunchSpec {
            auth_token: "tok".into(),
            subverters: vec!["/mods/game.dll".into(), " ".into()],
            res_packs: vec!["/packs/HiTech".into()],
            ..LaunchSpec::default()
        };
        let env = build_env(&spec);
        assert!(env.contains(&("SS14_LOADER_SUBVERTERS".into(), "/mods/game.dll".into())));
        assert!(env.contains(&("SS14_LOADER_RES_PACKS".into(), "/packs/HiTech".into())));
        assert!(!env.iter().any(|(key, _)| key == "ILLUSIO_DUMP"));
    }

    #[test]
    fn env_sets_dump_dir_per_fork() {
        let spec = LaunchSpec {
            auth_token: "tok".into(),
            dump_resources: true,
            build_fork_id: "HiTech/Fork v2".into(),
            ..LaunchSpec::default()
        };
        let env = build_env(&spec);
        let dump = env
            .iter()
            .find(|(key, _)| key == "SS14_LOADER_DUMP_DIR")
            .map(|(_, value)| value.clone())
            .unwrap_or_default();
        assert!(dump.contains("HiTech_Fork_v2"));
        assert!(env.contains(&("ILLUSIO_DUMP".into(), "1".into())));
        let empty = LaunchSpec {
            auth_token: "tok".into(),
            dump_resources: true,
            ..LaunchSpec::default()
        };
        let env = build_env(&empty);
        assert!(env
            .iter()
            .any(|(key, value)| key == "SS14_LOADER_DUMP_DIR" && value.contains("unknown")));
    }

    #[test]
    fn sanitizes_fork_ids() {
        assert_eq!(sanitize_fork_id("space_wizards"), "space_wizards");
        assert_eq!(sanitize_fork_id("Corvax/Warden:42"), "Corvax_Warden_42");
        assert_eq!(sanitize_fork_id("  "), "unknown");
        assert_eq!(sanitize_fork_id("///"), "___");
    }

    #[test]
    fn env_carries_stealth_hwid_pgo() {
        let spec = LaunchSpec {
            auth_token: "tok".into(),
            hide_level: 3,
            hwid_mode: "fixed".into(),
            hwid_value: "0xABCD".into(),
            hwid_optout: true,
            dynamic_pgo: true,
            ..LaunchSpec::default()
        };
        let env = build_env(&spec);
        assert!(env.contains(&("ILLUSIO_HIDE_LEVEL".into(), "3".into())));
        assert!(env.contains(&("ILLUSIO_HWID_MODE".into(), "fixed".into())));
        assert!(env.contains(&("ILLUSIO_HWID_VALUE".into(), "abcd".into())));
        assert!(env.contains(&("ROBUST_AUTH_ALLOW_HWID".into(), "0".into())));
        assert!(env.contains(&("DOTNET_TieredPGO".into(), "1".into())));
    }

    #[test]
    fn env_carries_backports_and_rpc() {
        let spec = LaunchSpec {
            auth_token: "tok".into(),
            build_fork_id: "My Fork".into(),
            build_engine_version: "210.1.0".into(),
            backports: true,
            backports_no_any: true,
            rpc_fake: true,
            rpc_fake_name: "Guest".into(),
            ..LaunchSpec::default()
        };
        let env = build_env(&spec);
        assert!(env.contains(&("ILLUSIO_BACKPORTS".into(), "1".into())));
        assert!(env.contains(&("ILLUSIO_NO_ANY_BACKPORTS".into(), "1".into())));
        assert!(env.contains(&("ILLUSIO_FORK_ID".into(), "My_Fork".into())));
        assert!(env.contains(&("ILLUSIO_ENGINE_VER".into(), "210.1.0".into())));
        assert!(env.contains(&("ILLUSIO_RPC_FAKE".into(), "1".into())));
        assert!(env.contains(&("ILLUSIO_RPC_USERNAME".into(), "Guest".into())));
    }

    #[test]
    fn env_omits_disabled_backports_and_rpc() {
        let spec = LaunchSpec {
            auth_token: "tok".into(),
            ..LaunchSpec::default()
        };
        let env = build_env(&spec);
        assert!(!env.iter().any(|(key, _)| key == "ILLUSIO_BACKPORTS"));
        assert!(!env.iter().any(|(key, _)| key == "ILLUSIO_RPC_FAKE"));
    }

    #[test]
    fn legacy_hwid_flag_maps_to_random() {
        let spec = LaunchSpec {
            auth_token: "tok".into(),
            patch_hwid: true,
            hide_level: 2,
            ..LaunchSpec::default()
        };
        let env = build_env(&spec);
        assert!(env.contains(&("ILLUSIO_HWID_MODE".into(), "random".into())));
        assert!(env.contains(&("ILLUSIO_HIDE_LEVEL".into(), "2".into())));
    }

    #[test]
    fn invalid_hwid_falls_back_to_random() {
        let spec = LaunchSpec {
            auth_token: "tok".into(),
            hwid_mode: "fixed".into(),
            hwid_value: "zzz".into(),
            ..LaunchSpec::default()
        };
        let env = build_env(&spec);
        assert!(env.contains(&("ILLUSIO_HWID_MODE".into(), "random".into())));
        assert!(!env.iter().any(|(key, _)| key == "ILLUSIO_HWID_VALUE"));
    }

    #[test]
    fn fuse_blocks_hidden_engine_without_stealth() {
        assert!(stealth_fuse(2, "240.4.0").is_ok());
        assert!(stealth_fuse(0, "182.0.0").is_ok());
        let result = stealth_fuse(0, "240.4.0");
        assert!(result.is_err());
    }

    #[test]
    fn normalizes_hwid_values() {
        assert_eq!(normalize_hwid(" 0xABCD ").as_deref(), Some("abcd"));
        assert_eq!(normalize_hwid("AABB"), Some("aabb".to_string()));
        assert_eq!(normalize_hwid("abc"), None);
        assert_eq!(normalize_hwid(""), None);
        assert_eq!(normalize_hwid("xy"), None);
    }

    #[test]
    fn normalizes_admin_guids() {
        assert_eq!(
            normalize_guid("{0123456789ABCDEF0123456789abcdef}").as_deref(),
            Some("0123456789abcdef0123456789abcdef")
        );
        assert_eq!(normalize_guid("short"), None);
        assert_eq!(normalize_guid("zz23456789abcdef0123456789abcdef"), None);
        assert_eq!(normalize_guid(""), None);
    }

    #[test]
    fn env_carries_patchless_and_modules() {
        let spec = LaunchSpec {
            auth_token: "tok".into(),
            patchless: true,
            stealth_registries: true,
            mod_logs: true,
            modules: vec![
                "Robust.Client".into(),
                " ".into(),
                "Robust.Client.WebView".into(),
            ],
            ..LaunchSpec::default()
        };
        let env = build_env(&spec);
        assert!(env.contains(&("ILLUSIO_PATCHLESS".into(), "1".into())));
        assert!(env.contains(&("ILLUSIO_STEALTH_REGISTRIES".into(), "1".into())));
        assert!(env.contains(&("ILLUSIO_MOD_LOGS".into(), "1".into())));
        assert!(env.iter().any(|(key, _)| key == "ILLUSIO_LOGS_DIR"));
        assert!(env.contains(&("ROBUST_MODULE_ROBUST_CLIENT".into(), "Robust.Client".into())));
        assert!(env.contains(&(
            "ROBUST_MODULE_ROBUST_CLIENT_WEBVIEW".into(),
            "Robust.Client.WebView".into()
        )));
        let disabled = build_env(&LaunchSpec {
            auth_token: "tok".into(),
            ..LaunchSpec::default()
        });
        assert!(!disabled.iter().any(|(key, _)| key == "ILLUSIO_PATCHLESS"));
        assert!(!disabled
            .iter()
            .any(|(key, _)| key == "ILLUSIO_STEALTH_REGISTRIES"));
    }

    #[test]
    fn admin_guid_replaces_user_id() {
        let spec = LaunchSpec {
            auth_token: "tok".into(),
            auth_user_id: "real-guid".into(),
            admin_guid: true,
            admin_guid_value: "0123456789ABCDEF0123456789ABCDEF".into(),
            ..LaunchSpec::default()
        };
        let env = build_env(&spec);
        assert!(env.contains(&(
            "ROBUST_AUTH_USERID".into(),
            "0123456789abcdef0123456789abcdef".into()
        )));
        let invalid = LaunchSpec {
            auth_token: "tok".into(),
            auth_user_id: "real-guid".into(),
            admin_guid: true,
            admin_guid_value: "nope".into(),
            ..LaunchSpec::default()
        };
        let env = build_env(&invalid);
        assert!(env.contains(&("ROBUST_AUTH_USERID".into(), "real-guid".into())));
        let off = LaunchSpec {
            auth_token: "tok".into(),
            auth_user_id: "real-guid".into(),
            admin_guid_value: "0123456789abcdef0123456789abcdef".into(),
            ..LaunchSpec::default()
        };
        let env = build_env(&off);
        assert!(env.contains(&("ROBUST_AUTH_USERID".into(), "real-guid".into())));
    }

    #[test]
    fn launch_status_defaults() {
        let status = status_snapshot();
        assert!(!status.running);
        assert!(!status.crashed);
        assert_eq!(status.pid, 0);
    }

    #[test]
    fn loader_launch_requires_files() {
        let mut spec = spec();
        spec.mode = "acz".into();
        spec.loader_dir = "/nonexistent/loader".into();
        assert!(launch(&spec).is_err());
    }
}

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::process::{Command, Stdio};

use crate::config::ProxyConfig;
use crate::socks::{parse_udp_address, prepare_udp_relay, PreparedRelay};

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

pub fn build_env(spec: &LaunchSpec) -> Vec<(String, String)> {
    let mut env = Vec::new();
    let token = spec.auth_token.trim();
    if token.is_empty() {
        return env;
    }
    env.push(("ROBUST_AUTH_TOKEN".into(), token.to_string()));
    let user_id = spec.auth_user_id.trim();
    if !user_id.is_empty() {
        env.push(("ROBUST_AUTH_USERID".into(), user_id.to_string()));
    }
    let pubkey = spec.auth_pubkey.trim();
    if !pubkey.is_empty() {
        env.push(("ROBUST_AUTH_PUBKEY".into(), pubkey.to_string()));
    }
    let server = spec.auth_server.trim();
    if !server.is_empty() {
        env.push(("ROBUST_AUTH_SERVER".into(), server.to_string()));
    }
    let mods: Vec<String> = spec
        .mods
        .iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect();
    if !mods.is_empty() {
        env.push(("SS14_LOADER_OVERLAY_ZIPS".into(), mods.join(";")));
    }
    let dlls: Vec<String> = spec
        .mod_dlls
        .iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect();
    if !dlls.is_empty() {
        env.push(("SS14_LOADER_MOD_DLLS".into(), dlls.join(";")));
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
    env
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
    if let Some(relay) = relay {
        relay.start(child);
    } else {
        drop(child);
    }
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
    if let Some(relay) = relay {
        relay.start(child);
    } else {
        drop(child);
    }
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
    fn loader_launch_requires_files() {
        let mut spec = spec();
        spec.mode = "acz".into();
        spec.loader_dir = "/nonexistent/loader".into();
        assert!(launch(&spec).is_err());
    }
}

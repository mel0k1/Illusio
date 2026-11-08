use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::{Command, Stdio};

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
    env
}

pub fn launch(spec: &LaunchSpec) -> Result<u32, String> {
    let path = client_path(&spec.install_dir);
    if !path.exists() {
        return Err(format!("клиент не найден: {}", path.display()));
    }
    let mut command = Command::new(&path);
    command
        .args(build_args(spec))
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    for (key, value) in build_env(spec) {
        command.env(key, value);
    }
    let child = command
        .spawn()
        .map_err(|error| format!("не удалось запустить клиент: {error}"))?;
    Ok(child.id())
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
}

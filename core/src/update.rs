use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

use crate::remote;

pub const RELEASES_API: &str = "https://api.github.com/repos/mel0k1/Illusio/releases/latest";

#[derive(Debug, Clone, Default, Serialize)]
pub struct ReleaseCheck {
    pub available: bool,
    pub version: String,
    pub notes: String,
    #[serde(rename = "assetName")]
    pub asset_name: String,
    #[serde(rename = "assetUrl")]
    pub asset_url: String,
}

#[derive(Debug, Deserialize)]
struct ReleasePayload {
    #[serde(default, rename = "tag_name")]
    tag_name: String,
    #[serde(default, rename = "body")]
    body: String,
    #[serde(default, rename = "assets")]
    assets: Vec<AssetPayload>,
}

#[derive(Debug, Deserialize)]
struct AssetPayload {
    #[serde(default)]
    name: String,
    #[serde(default, rename = "browser_download_url")]
    browser_download_url: String,
}

pub fn platform_asset_suffix() -> &'static str {
    if cfg!(target_os = "windows") {
        "-windows-x64.zip"
    } else if cfg!(target_os = "macos") {
        "-macos-arm64.zip"
    } else {
        "-linux-x64.tar.gz"
    }
}

fn update_client() -> Result<reqwest::blocking::Client, String> {
    crate::http::with_route(
        reqwest::blocking::Client::builder(),
        crate::http::Route::Updates,
    )
    .timeout(Duration::from_secs(20))
    .user_agent(format!("Illusio/{}", env!("CARGO_PKG_VERSION")))
    .build()
    .map_err(|error| error.to_string())
}

pub fn check(current_version: &str) -> Result<ReleaseCheck, String> {
    let client = update_client()?;
    let response = client
        .get(RELEASES_API)
        .send()
        .map_err(|error| error.to_string())?;
    let response = response
        .error_for_status()
        .map_err(|error| format!("GitHub ответил с ошибкой: {error}"))?;
    let release: ReleasePayload = response
        .json()
        .map_err(|error| format!("не удалось разобрать релиз: {error}"))?;
    let version = release.tag_name.trim().trim_start_matches('v').to_string();
    let suffix = platform_asset_suffix();
    let asset = release
        .assets
        .iter()
        .find(|value| value.name.ends_with(suffix) && !value.name.contains("setup"));
    let Some(asset) = asset else {
        return Ok(ReleaseCheck::default());
    };
    let available = remote::version_is_below(current_version, &version);
    Ok(ReleaseCheck {
        available,
        version,
        notes: release.body,
        asset_name: asset.name.clone(),
        asset_url: asset.browser_download_url.clone(),
    })
}

pub fn download_asset(url: &str, dest_dir: &Path, name: &str) -> Result<PathBuf, String> {
    fs::create_dir_all(dest_dir).map_err(|error| error.to_string())?;
    let dest = dest_dir.join(name);
    let client = update_client()?;
    let mut response = client
        .get(url)
        .send()
        .map_err(|error| error.to_string())?
        .error_for_status()
        .map_err(|error| format!("GitHub ответил с ошибкой: {error}"))?;
    let mut file = fs::File::create(&dest).map_err(|error| error.to_string())?;
    let mut buffer = [0u8; 65_536];
    loop {
        let read = response
            .read(&mut buffer)
            .map_err(|error| format!("обрыв загрузки: {error}"))?;
        if read == 0 {
            break;
        }
        file.write_all(&buffer[..read])
            .map_err(|error| error.to_string())?;
    }
    file.flush().map_err(|error| error.to_string())?;
    Ok(dest)
}

fn exe_path() -> Result<PathBuf, String> {
    std::env::current_exe().map_err(|error| format!("не удалось определить путь лаунчера: {error}"))
}

fn script_dir() -> PathBuf {
    std::env::temp_dir().join(format!("illusio-update-{}", std::process::id()))
}

fn spawn_detached(mut command: Command) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        const DETACHED_PROCESS: u32 = 0x0000_0008;
        command
            .creation_flags(CREATE_NO_WINDOW | DETACHED_PROCESS)
            .spawn()
            .map_err(|error| error.to_string())?;
    }
    #[cfg(not(target_os = "windows"))]
    {
        command
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .stdin(std::process::Stdio::null())
            .spawn()
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn apply_windows(
    archive: &Path,
    extracted: &Path,
    install: &Path,
    exe: &Path,
) -> Result<(), String> {
    crate::install::extract_zip(archive, extracted)?;
    let pid = std::process::id();
    let script = script_dir().join("update.cmd");
    fs::create_dir_all(script.parent().unwrap()).map_err(|error| error.to_string())?;
    let body = format!(
        "@echo off\r\n:wait\r\ntasklist /FI \"PID eq {pid}\" 2>nul | find \"{pid}\" >nul\r\nif not errorlevel 1 (\r\n  timeout /t 1 /nobreak >nul\r\n  goto wait\r\n)\r\nrobocopy \"{src}\" \"{dst}\" /E /NFL /NDL /NJH /NJS >nul\r\nstart \"\" \"{exe}\"\r\ndel \"%~f0\"\r\n",
        src = extracted.display(),
        dst = install.display(),
        exe = exe.display(),
    );
    fs::write(&script, body).map_err(|error| error.to_string())?;
    let mut command = Command::new("cmd");
    command
        .arg("/c")
        .arg(&script)
        .current_dir(script.parent().unwrap());
    spawn_detached(command)
}

#[cfg(target_os = "linux")]
fn apply_linux(archive: &Path, install: &Path, exe: &Path) -> Result<(), String> {
    let pid = std::process::id();
    let script = script_dir().join("update.sh");
    fs::create_dir_all(script.parent().unwrap()).map_err(|error| error.to_string())?;
    let body = format!(
        "#!/bin/sh\nwhile kill -0 {pid} 2>/dev/null; do sleep 1; done\ntar -xzf '{archive}' -C '{install}'\nchmod +x '{exe}'\nnohup '{exe}' >/dev/null 2>&1 &\nrm -f \"$0\"\n",
        archive = archive.display(),
        install = install.display(),
        exe = exe.display(),
    );
    fs::write(&script, body).map_err(|error| error.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&script, fs::Permissions::from_mode(0o755))
            .map_err(|error| error.to_string())?;
    }
    let mut command = Command::new("/bin/sh");
    command.arg(&script);
    spawn_detached(command)
}

#[cfg(target_os = "macos")]
fn apply_macos(
    archive: &Path,
    extracted: &Path,
    app_dir: &Path,
    app_path: &Path,
) -> Result<(), String> {
    crate::install::extract_zip(archive, extracted)?;
    let pid = std::process::id();
    let script = script_dir().join("update.sh");
    fs::create_dir_all(script.parent().unwrap()).map_err(|error| error.to_string())?;
    let body = format!(
        "#!/bin/sh\nwhile kill -0 {pid} 2>/dev/null; do sleep 1; done\nrm -rf '{app}'\nunzip -q -o '{zip}' -d '{dir}'\nopen '{app}'\nrm -f \"$0\"\n",
        app = app_path.display(),
        zip = archive.display(),
        dir = app_dir.display(),
    );
    fs::write(&script, body).map_err(|error| error.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&script, fs::Permissions::from_mode(0o755))
            .map_err(|error| error.to_string())?;
    }
    let mut command = Command::new("/bin/sh");
    command.arg(&script);
    spawn_detached(command)
}

pub fn apply(archive: &Path) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        let exe = exe_path()?;
        let install = exe
            .parent()
            .ok_or_else(|| "не удалось определить каталог установки".to_string())?
            .to_path_buf();
        let extracted = script_dir().join("files");
        return apply_windows(archive, &extracted, &install, &exe);
    }
    #[cfg(target_os = "macos")]
    {
        let exe = exe_path()?;
        let app_path = exe
            .parent()
            .and_then(|value| value.parent())
            .and_then(|value| value.parent())
            .ok_or_else(|| "не удалось определить каталог приложения".to_string())?
            .to_path_buf();
        let app_dir = app_path
            .parent()
            .ok_or_else(|| "не удалось определить каталог приложения".to_string())?
            .to_path_buf();
        let extracted = script_dir().join("files");
        return apply_macos(archive, &extracted, &app_dir, &app_path);
    }
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        let exe = exe_path()?;
        let install = exe
            .parent()
            .ok_or_else(|| "не удалось определить каталог установки".to_string())?
            .to_path_buf();
        apply_linux(archive, &install, &exe)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_newer_release() {
        assert!(remote::version_is_below("0.4.0", "0.5.0"));
        assert!(!remote::version_is_below("0.5.0", "0.5.0"));
    }

    #[test]
    fn picks_platform_suffix() {
        let suffix = platform_asset_suffix();
        if cfg!(target_os = "windows") {
            assert_eq!(suffix, "-windows-x64.zip");
        } else if cfg!(target_os = "macos") {
            assert_eq!(suffix, "-macos-arm64.zip");
        } else {
            assert_eq!(suffix, "-linux-x64.tar.gz");
        }
    }
}

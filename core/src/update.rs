use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

fn version_parts(value: &str) -> Vec<u64> {
    value
        .trim()
        .trim_start_matches('v')
        .split('.')
        .map(|part| {
            part.chars()
                .take_while(|c| c.is_ascii_digit())
                .collect::<String>()
                .parse()
                .unwrap_or(0)
        })
        .collect()
}

pub fn version_is_below(current: &str, minimum: &str) -> bool {
    let minimum = minimum.trim();
    if minimum.is_empty() {
        return false;
    }
    let left = version_parts(current);
    let right = version_parts(minimum);
    let width = left.len().max(right.len());
    for index in 0..width {
        let a = left.get(index).copied().unwrap_or(0);
        let b = right.get(index).copied().unwrap_or(0);
        if a != b {
            return a < b;
        }
    }
    false
}

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
    let available = version_is_below(current_version, &version);
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
    let script = script_dir().join("update.ps1");
    fs::create_dir_all(script.parent().unwrap()).map_err(|error| error.to_string())?;
    let body = format!(
        "$deadline = (Get-Date).AddSeconds(60)\r\nwhile (Get-Process -Id {pid} -ErrorAction SilentlyContinue) {{\r\n  Start-Sleep -Milliseconds 500\r\n  if ((Get-Date) -gt $deadline) {{ break }}\r\n}}\r\nfunction Copy-Stage([string]$src, [string]$dst) {{\r\n  try {{\r\n    Copy-Item -LiteralPath $src -Destination $dst -Force\r\n  }} catch {{\r\n    Copy-Item -LiteralPath $src -Destination ($dst + '.pending') -Force\r\n  }}\r\n}}\r\nfunction Copy-Tree([string]$root, [string]$out) {{\r\n  New-Item -ItemType Directory -Force -Path $out | Out-Null\r\n  Get-ChildItem -LiteralPath $root -Recurse -Force | ForEach-Object {{\r\n    $rel = $_.FullName.Substring($root.Length).TrimStart('\\', '/')\r\n    if ($rel.Length -eq 0) {{ return }}\r\n    $dst = Join-Path $out $rel\r\n    if ($_.PSIsContainer) {{\r\n      New-Item -ItemType Directory -Force -Path $dst | Out-Null\r\n    }} else {{\r\n      Copy-Stage $_.FullName $dst\r\n    }}\r\n  }}\r\n}}\r\nCopy-Tree '{src}' '{dst}'\r\nStart-Process -FilePath '{exe}'\r\n",
        pid = pid,
        src = ps_escape(&extracted.display().to_string()),
        dst = ps_escape(&install.display().to_string()),
        exe = ps_escape(&exe.display().to_string()),
    );
    fs::write(&script, body).map_err(|error| error.to_string())?;
    let mut command = Command::new("powershell");
    command
        .args([
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-WindowStyle",
            "Hidden",
        ])
        .arg(&script)
        .current_dir(script.parent().unwrap());
    spawn_detached(command)
}

#[cfg(target_os = "windows")]
fn ps_escape(value: &str) -> String {
    value.replace('\'', "''")
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

pub fn finalize_pending() -> Result<usize, String> {
    let exe = exe_path()?;
    let Some(install) = exe.parent() else {
        return Ok(0);
    };
    let mut applied = 0;
    let mut failures = Vec::new();
    apply_pending_dir(install, &mut applied, &mut failures);
    if applied == 0 && failures.is_empty() {
        return Ok(0);
    }
    if failures.is_empty() {
        return Ok(applied);
    }
    Err(failures.join("; "))
}

fn apply_pending_dir(dir: &Path, applied: &mut usize, failures: &mut Vec<String>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            apply_pending_dir(&path, applied, failures);
            continue;
        }

        let name = entry.file_name().to_string_lossy().to_string();
        if !name.ends_with(".pending") {
            continue;
        }

        let target_name = name.trim_end_matches(".pending").to_string();
        if target_name.is_empty() {
            continue;
        }

        let target = dir.join(&target_name);
        unlock(&target);
        let result = fs::rename(&path, &target).or_else(|_| {
            if target.exists() {
                fs::remove_file(&target).ok();
            }
            fs::copy(&path, &target).and_then(|_| fs::remove_file(&path))
        });
        match result {
            Ok(_) => *applied += 1,
            Err(error) => failures.push(format!("{target_name}: {error}")),
        }
    }
}

fn unlock(path: &Path) {
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        let _ = Command::new("attrib")
            .args(["-R", "-H", "-S"])
            .arg(path)
            .creation_flags(CREATE_NO_WINDOW)
            .status();
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = path;
    }
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
        assert!(version_is_below("0.4.0", "0.5.0"));
        assert!(!version_is_below("0.5.0", "0.5.0"));
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

    #[test]
    fn applies_pending_files() {
        let base = std::env::temp_dir().join(format!("illusio-pending-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let nested = base.join("sub");
        fs::create_dir_all(&nested).unwrap();
        fs::write(base.join("Illusio.exe.pending"), "new").unwrap();
        fs::write(base.join("Illusio.exe"), "old").unwrap();
        fs::write(nested.join("lib.dll.pending"), "newlib").unwrap();

        let mut applied = 0;
        let mut failures = Vec::new();
        apply_pending_dir(&base, &mut applied, &mut failures);
        assert_eq!(applied, 2);
        assert!(failures.is_empty());
        assert_eq!(fs::read_to_string(base.join("Illusio.exe")).unwrap(), "new");
        assert_eq!(
            fs::read_to_string(nested.join("lib.dll")).unwrap(),
            "newlib"
        );
        assert!(!base.join("Illusio.exe.pending").exists());
        let _ = fs::remove_dir_all(&base);
    }
}

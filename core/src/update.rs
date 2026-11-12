use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Mutex, OnceLock};
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
pub const RELEASES_LIST_API: &str =
    "https://api.github.com/repos/mel0k1/Illusio/releases?per_page=10";

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
    #[serde(default, deserialize_with = "null_to_default", rename = "tag_name")]
    tag_name: String,
    #[serde(default, deserialize_with = "null_to_default", rename = "body")]
    body: String,
    #[serde(default, deserialize_with = "null_to_default", rename = "prerelease")]
    prerelease: bool,
    #[serde(default, deserialize_with = "null_to_default", rename = "published_at")]
    published_at: String,
    #[serde(default, deserialize_with = "null_to_default", rename = "assets")]
    assets: Vec<AssetPayload>,
}

#[derive(Debug, Deserialize)]
struct AssetPayload {
    #[serde(default, deserialize_with = "null_to_default")]
    name: String,
    #[serde(
        default,
        deserialize_with = "null_to_default",
        rename = "browser_download_url"
    )]
    browser_download_url: String,
}

fn null_to_default<'de, D, T>(deserializer: D) -> Result<T, D::Error>
where
    D: serde::Deserializer<'de>,
    T: Default + serde::Deserialize<'de>,
{
    let value: Option<T> = Option::deserialize(deserializer)?;
    Ok(value.unwrap_or_default())
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct ReleaseEntry {
    pub version: String,
    pub prerelease: bool,
    pub published: String,
    #[serde(rename = "assetName")]
    pub asset_name: String,
    #[serde(rename = "assetUrl")]
    pub asset_url: String,
    pub current: bool,
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
    .connect_timeout(Duration::from_secs(20))
    .timeout(Duration::from_secs(20))
    .user_agent(format!("Illusio/{}", env!("CARGO_PKG_VERSION")))
    .build()
    .map_err(|error| error.to_string())
}

fn download_client() -> Result<reqwest::blocking::Client, String> {
    crate::http::with_route(
        reqwest::blocking::Client::builder(),
        crate::http::Route::Updates,
    )
    .connect_timeout(Duration::from_secs(20))
    .timeout(Duration::from_secs(3600))
    .user_agent(format!("Illusio/{}", env!("CARGO_PKG_VERSION")))
    .build()
    .map_err(|error| error.to_string())
}

pub fn check(current_version: &str) -> Result<ReleaseCheck, String> {
    check_ex(current_version, false)
}

pub fn check_ex(current_version: &str, prerelease: bool) -> Result<ReleaseCheck, String> {
    let client = update_client()?;
    let response = client
        .get(RELEASES_LIST_API)
        .send()
        .map_err(|error| error.to_string())?;
    let response = response
        .error_for_status()
        .map_err(|error| format!("GitHub ответил с ошибкой: {error}"))?;
    let body = response.text().map_err(|error| error.to_string())?;
    let releases: Vec<ReleasePayload> = serde_json::from_str(&body)
        .map_err(|error| format!("не удалось разобрать релизы: {error}"))?;
    let suffix = platform_asset_suffix();
    let target = releases
        .into_iter()
        .filter(|release| prerelease || !release.prerelease)
        .find(|release| pick_asset(&release.assets, suffix).is_some())
        .ok_or_else(|| {
            if prerelease {
                "в канале pre-release пока нет ни одного релиза".to_string()
            } else {
                "в списке релизов нет сборки для этой платформы".to_string()
            }
        })?;
    let version = target.tag_name.trim().trim_start_matches('v').to_string();
    let Some(asset) = pick_asset(&target.assets, suffix) else {
        return Ok(ReleaseCheck::default());
    };
    let available = version_is_below(current_version, &version);
    Ok(ReleaseCheck {
        available,
        version,
        notes: target.body,
        asset_name: asset.name.clone(),
        asset_url: asset.browser_download_url.clone(),
    })
}

fn pick_asset<'a>(assets: &'a [AssetPayload], suffix: &str) -> Option<&'a AssetPayload> {
    assets
        .iter()
        .find(|value| value.name.ends_with(suffix) && !value.name.contains("setup"))
}

pub fn parse_releases(body: &str, current_version: &str) -> Result<Vec<ReleaseEntry>, String> {
    let releases: Vec<ReleasePayload> = serde_json::from_str(body)
        .map_err(|error| format!("не удалось разобрать релизы: {error}"))?;
    let suffix = platform_asset_suffix();
    let mut entries = Vec::new();
    for release in releases {
        let version = release.tag_name.trim().trim_start_matches('v').to_string();
        if version.is_empty() {
            continue;
        }
        let Some(asset) = pick_asset(&release.assets, suffix) else {
            continue;
        };
        entries.push(ReleaseEntry {
            current: version == current_version,
            version,
            prerelease: release.prerelease,
            published: release
                .published_at
                .split('T')
                .next()
                .unwrap_or_default()
                .to_string(),
            asset_name: asset.name.clone(),
            asset_url: asset.browser_download_url.clone(),
        });
    }
    Ok(entries)
}

pub fn list_releases(current_version: &str) -> Result<Vec<ReleaseEntry>, String> {
    let client = update_client()?;
    let response = client
        .get(RELEASES_LIST_API)
        .send()
        .map_err(|error| error.to_string())?;
    let response = response
        .error_for_status()
        .map_err(|error| format!("GitHub ответил с ошибкой: {error}"))?;
    let body = response.text().map_err(|error| error.to_string())?;
    parse_releases(&body, current_version)
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct ReleaseState {
    pub phase: String,
    pub downloaded: u64,
    pub total: u64,
    pub message: String,
    pub error: String,
    pub running: bool,
}

struct ReleaseJob {
    state: Mutex<ReleaseState>,
}

static RELEASE_JOB: OnceLock<ReleaseJob> = OnceLock::new();

fn release_job() -> &'static ReleaseJob {
    RELEASE_JOB.get_or_init(|| ReleaseJob {
        state: Mutex::new(ReleaseState::default()),
    })
}

fn set_release_state(patch: impl FnOnce(&mut ReleaseState)) {
    if let Ok(mut state) = release_job().state.lock() {
        patch(&mut state);
    }
}

pub fn release_progress() -> ReleaseState {
    release_job()
        .state
        .lock()
        .map(|state| state.clone())
        .unwrap_or_default()
}

static RELEASE_RUNNING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

struct ReleaseGuard;

impl Drop for ReleaseGuard {
    fn drop(&mut self) {
        RELEASE_RUNNING.store(false, std::sync::atomic::Ordering::SeqCst);
    }
}

fn is_allowed_asset_url(raw: &str) -> bool {
    let trimmed = raw.trim();
    let Some((scheme, rest)) = trimmed.split_once("://") else {
        return false;
    };
    if !scheme.eq_ignore_ascii_case("https") {
        return false;
    }
    let (authority, path) = match rest.find('/') {
        Some(index) => (&rest[..index], &rest[index..]),
        None => (rest, ""),
    };
    let host = authority
        .rsplit_once('@')
        .map(|(_, host)| host)
        .unwrap_or(authority);
    let host = host
        .split(':')
        .next()
        .unwrap_or("")
        .trim_matches(['[', ']'])
        .to_ascii_lowercase();
    if host == "objects.githubusercontent.com" {
        return true;
    }
    if host == "github.com" {
        return path
            .to_ascii_lowercase()
            .starts_with("/mel0k1/illusio/releases");
    }
    false
}

pub fn install_release(asset_url: &str, asset_name: &str) -> Result<(), String> {
    if asset_url.trim().is_empty() || asset_name.trim().is_empty() {
        set_release_state(|state| {
            state.phase = "error".into();
            state.error = "не указан файл релиза".into();
            state.running = false;
        });
        return Err("не указан файл релиза".into());
    }
    if !is_allowed_asset_url(asset_url) {
        set_release_state(|state| {
            state.phase = "error".into();
            state.error = "недопустимый адрес файла релиза".into();
            state.running = false;
        });
        return Err("недопустимый адрес файла релиза".into());
    }
    if RELEASE_RUNNING.swap(true, std::sync::atomic::Ordering::SeqCst) {
        return Err("обновление уже выполняется".into());
    }
    let _guard = ReleaseGuard;
    set_release_state(|state| {
        state.phase = "download".into();
        state.downloaded = 0;
        state.total = 0;
        state.message = "загружаем сборку лаунчера".into();
        state.error = String::new();
        state.running = true;
    });
    let archive = match download_asset(
        asset_url,
        &std::env::temp_dir().join("illusio-update"),
        asset_name,
    ) {
        Ok(value) => value,
        Err(message) => {
            set_release_state(|state| {
                state.phase = "error".into();
                state.error = message.clone();
                state.running = false;
            });
            return Err(message);
        }
    };
    set_release_state(|state| {
        state.phase = "install".into();
        state.downloaded = 0;
        state.total = 0;
        state.message = "устанавливаем обновление".into();
    });
    match apply(&archive) {
        Ok(()) => {
            set_release_state(|state| {
                state.phase = "done".into();
                state.message = "обновление установлено".into();
                state.running = false;
            });
            Ok(())
        }
        Err(message) => {
            set_release_state(|state| {
                state.phase = "error".into();
                state.error = message.clone();
                state.running = false;
            });
            Err(message)
        }
    }
}

pub fn download_asset(url: &str, dest_dir: &Path, name: &str) -> Result<PathBuf, String> {
    let clean = Path::new(name)
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| "некорректное имя файла".to_string())?;
    fs::create_dir_all(dest_dir).map_err(|error| error.to_string())?;
    let dest = dest_dir.join(clean);
    let client = download_client()?;
    let mut response = client
        .get(url)
        .send()
        .map_err(|error| error.to_string())?
        .error_for_status()
        .map_err(|error| format!("GitHub ответил с ошибкой: {error}"))?;
    let total = response
        .headers()
        .get(reqwest::header::CONTENT_LENGTH)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(0);
    set_release_state(|state| {
        state.total = total;
        state.downloaded = 0;
    });
    let mut file = fs::File::create(&dest).map_err(|error| error.to_string())?;
    let mut buffer = [0u8; 65_536];
    let mut downloaded: u64 = 0;
    loop {
        let read = response
            .read(&mut buffer)
            .map_err(|error| format!("обрыв загрузки: {error}"))?;
        if read == 0 {
            break;
        }
        file.write_all(&buffer[..read])
            .map_err(|error| error.to_string())?;
        downloaded += read as u64;
        set_release_state(|state| state.downloaded = downloaded);
    }
    file.flush().map_err(|error| error.to_string())?;
    if total > 0 && downloaded != total {
        fs::remove_file(&dest).ok();
        return Err(format!(
            "загрузка оборвалась: получено {downloaded} из {total} байт"
        ));
    }
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
fn sh_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

#[cfg(target_os = "linux")]
fn apply_linux(archive: &Path, install: &Path, exe: &Path) -> Result<(), String> {
    let pid = std::process::id();
    let script = script_dir().join("update.sh");
    fs::create_dir_all(script.parent().unwrap()).map_err(|error| error.to_string())?;
    let install_name = install
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("illusio")
        .to_string();
    let stage = install
        .parent()
        .unwrap_or(Path::new("."))
        .join(format!("{install_name}.update.new"));
    let old = install
        .parent()
        .unwrap_or(Path::new("."))
        .join(format!("{install_name}.update.old"));
    let body = format!(
        "#!/bin/sh\nset -e\nwhile kill -0 {pid} 2>/dev/null; do sleep 1; done\nrm -rf {stage} {old}\nmkdir -p {stage}\ntar -xzf {archive} -C {stage}\nif [ -d {install} ]; then\n  mv {install} {old}\nfi\nif ! mv {stage} {install}; then\n  if [ -d {old} ]; then mv {old} {install}; fi\n  exit 1\nfi\nrm -rf {old}\nchmod +x {exe}\nnohup {exe} >/dev/null 2>&1 &\nrm -f \"$0\"\n",
        pid = pid,
        archive = sh_quote(&archive.display().to_string()),
        install = sh_quote(&install.display().to_string()),
        stage = sh_quote(&stage.display().to_string()),
        old = sh_quote(&old.display().to_string()),
        exe = sh_quote(&exe.display().to_string()),
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
fn sh_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
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
    let stage = extracted.join("app");
    let stage_app = stage.join(
        app_path
            .file_name()
            .unwrap_or_else(|| std::ffi::OsStr::new("Illusio.app")),
    );
    let old = app_dir.join(format!(
        "{}.old",
        app_path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("Illusio.app")
    ));
    let body = format!(
        "#!/bin/sh\nset -e\nwhile kill -0 {pid} 2>/dev/null; do sleep 1; done\nrm -rf {stage} {old}\nmkdir -p {stage}\nunzip -q -o {zip} -d {stage}\nif [ ! -d {stage_app} ]; then\n  echo \"в архиве нет {app_name}\" >&2\n  exit 1\nfi\nif [ -d {app} ]; then\n  mv {app} {old}\nfi\nif ! mv {stage_app} {app}; then\n  if [ -d {old} ]; then mv {old} {app}; fi\n  exit 1\nfi\nrm -rf {old} {stage}\nopen {app}\nrm -f \"$0\"\n",
        pid = pid,
        zip = sh_quote(&archive.display().to_string()),
        stage = sh_quote(&stage.display().to_string()),
        stage_app = sh_quote(&stage_app.display().to_string()),
        app_name = app_path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("Illusio.app"),
        app = sh_quote(&app_path.display().to_string()),
        old = sh_quote(&old.display().to_string()),
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
    fn parses_release_list() {
        let asset = platform_asset_suffix();
        let body = format!(
            r#"[
            {{"tag_name":"v0.11.0","body":"- fixes","prerelease":true,"published_at":"2026-11-09T10:00:00Z","assets":[{{"name":"Illusio-0.11.0{asset}","browser_download_url":"https://example.com/a.zip"}}]}},
            {{"tag_name":"v0.10.0","body":null,"prerelease":false,"published_at":null,"assets":null}},
            {{"tag_name":"v0.9.0","body":"","prerelease":false,"published_at":"2026-10-01T10:00:00Z","assets":[{{"name":"Illusio-0.9.0-setup{asset}","browser_download_url":"https://example.com/s.zip"}}]}}
        ]"#
        );
        let releases = parse_releases(&body, "0.9.0").unwrap();
        assert_eq!(releases.len(), 1);
        assert_eq!(releases[0].version, "0.11.0");
        assert!(releases[0].prerelease);
        assert_eq!(releases[0].published, "2026-11-09");
        assert_eq!(releases[0].asset_name, format!("Illusio-0.11.0{asset}"));
        assert!(!releases[0].current);
    }

    #[test]
    fn marks_current_release() {
        let body = r#"[
            {"tag_name":"v0.10.0","prerelease":false,"published_at":"2026-11-01T10:00:00Z","assets":[{"name":"Illusio-0.10.0-linux-x64.tar.gz","browser_download_url":"https://example.com/l.tar.gz"}]},
            {"tag_name":"v0.9.0","prerelease":false,"published_at":"2026-10-01T10:00:00Z","assets":[{"name":"Illusio-0.9.0-linux-x64.tar.gz","browser_download_url":"https://example.com/o.tar.gz"}]}
        ]"#;
        let releases = parse_releases(body, "0.9.0").unwrap();
        assert_eq!(releases.len(), 2);
        assert!(!releases[0].current);
        assert!(releases[1].current);
    }

    #[test]
    fn rejects_path_names() {
        assert!(download_asset(
            "https://example.com/a.zip",
            std::path::Path::new("/tmp"),
            ".."
        )
        .is_err());
    }

    #[test]
    fn allowlists_release_urls() {
        assert!(super::is_allowed_asset_url(
            "https://github.com/mel0k1/Illusio/releases/download/v0.11.0/Illusio-0.11.0-linux-x64.tar.gz"
        ));
        assert!(super::is_allowed_asset_url(
            "https://objects.githubusercontent.com/some/path"
        ));
        assert!(!super::is_allowed_asset_url(
            "https://github.com/other/repo/releases/download/v1/a.zip"
        ));
        assert!(!super::is_allowed_asset_url(
            "http://github.com/mel0k1/Illusio/releases"
        ));
        assert!(!super::is_allowed_asset_url(
            "https://evil.example.com/a.zip"
        ));
        assert!(!super::is_allowed_asset_url(
            "github.com/mel0k1/Illusio/releases"
        ));
        assert!(!super::is_allowed_asset_url(""));
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

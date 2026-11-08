use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::Duration;

use crate::acz;
use crate::engine;

const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(20);
const STATUS_TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ServerBuild {
    #[serde(default, rename = "download_url")]
    pub download_url: String,
    #[serde(default, rename = "manifest_url")]
    pub manifest_url: String,
    #[serde(default, rename = "manifest_download_url")]
    pub manifest_download_url: String,
    #[serde(default, rename = "engine_version")]
    pub engine_version: String,
    #[serde(default)]
    pub version: String,
    #[serde(default, rename = "fork_id")]
    pub fork_id: String,
    #[serde(default)]
    pub hash: String,
    #[serde(default, rename = "manifest_hash")]
    pub manifest_hash: String,
    #[serde(default)]
    pub acz: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ServerAuthInfo {
    #[serde(default)]
    pub mode: i64,
    #[serde(default, rename = "public_key")]
    pub public_key: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ServerInfo {
    #[serde(default, rename = "connect_address")]
    pub connect_address: String,
    #[serde(default)]
    pub build: ServerBuild,
    #[serde(default)]
    pub auth: ServerAuthInfo,
    #[serde(default)]
    pub desc: String,
}

pub fn info_url(server_url: &str) -> String {
    format!("{}/info", server_url.trim_end_matches('/'))
}

fn status_client() -> Result<reqwest::blocking::Client, String> {
    reqwest::blocking::Client::builder()
        .timeout(STATUS_TIMEOUT)
        .build()
        .map_err(|error| error.to_string())
}

pub fn fetch_info(server_url: &str) -> Result<ServerInfo, String> {
    let client = status_client()?;
    let response = client
        .get(info_url(server_url))
        .send()
        .map_err(|error| error.to_string())?;
    let response = response
        .error_for_status()
        .map_err(|error| format!("сервер ответил с ошибкой: {error}"))?;
    response
        .json::<ServerInfo>()
        .map_err(|error| format!("не удалось разобрать /info: {error}"))
}

pub fn platform_name() -> &'static str {
    if cfg!(target_os = "windows") {
        "windows"
    } else if cfg!(target_os = "macos") {
        "macos"
    } else {
        "linux"
    }
}

pub fn zip_candidates(build: &ServerBuild) -> Vec<String> {
    let base = build.download_url.trim().trim_end_matches('/');
    if base.is_empty() {
        return Vec::new();
    }
    if base.to_ascii_lowercase().ends_with(".zip") {
        return vec![base.to_string()];
    }
    let mut candidates = Vec::new();
    let version = build.version.trim();
    let platform = platform_name();
    if !version.is_empty() {
        candidates.push(format!("{base}/{version}/{platform}.zip"));
    }
    candidates.push(format!("{base}/{platform}.zip"));
    candidates
}

pub fn default_install_dir() -> Option<PathBuf> {
    dirs::data_dir().map(|dir| dir.join("illusio").join("client"))
}

pub fn resolve_install_root(raw: &str) -> Result<PathBuf, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return default_install_dir()
            .ok_or_else(|| "не удалось определить каталог установки".into());
    }
    Ok(PathBuf::from(trimmed))
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct StoredBuild {
    #[serde(default)]
    pub version: String,
    #[serde(default, rename = "forkId")]
    pub fork_id: String,
    #[serde(default)]
    pub hash: String,
    #[serde(default, rename = "manifestHash")]
    pub manifest_hash: String,
    #[serde(default, rename = "engineVersion")]
    pub engine_version: String,
    #[serde(default)]
    pub acz: bool,
}

pub fn marker_path(dir: &Path) -> PathBuf {
    dir.join("version")
}

pub fn read_marker(dir: &Path) -> Option<StoredBuild> {
    let raw = fs::read_to_string(marker_path(dir)).ok()?;
    serde_json::from_str(&raw).ok()
}

pub fn write_marker(dir: &Path, build: &StoredBuild) -> Result<(), String> {
    let raw = serde_json::to_string_pretty(build).map_err(|error| error.to_string())?;
    fs::write(marker_path(dir), raw).map_err(|error| error.to_string())
}

fn build_matches(stored: &StoredBuild, build: &ServerBuild) -> bool {
    if stored.acz {
        let manifest_hash = build.manifest_hash.trim().to_ascii_lowercase();
        if !manifest_hash.is_empty() {
            return stored
                .manifest_hash
                .trim()
                .eq_ignore_ascii_case(&manifest_hash);
        }
    }
    let server_hash = build.hash.trim().to_ascii_lowercase();
    if !server_hash.is_empty() {
        return stored.hash.trim().eq_ignore_ascii_case(&server_hash);
    }
    let server_version = build.version.trim();
    if !server_version.is_empty() {
        return stored.version.trim() == server_version;
    }
    false
}

pub fn sha256_file(path: &Path) -> Result<String, String> {
    let mut file = fs::File::open(path).map_err(|error| error.to_string())?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 65536];
    loop {
        let read = file.read(&mut buffer).map_err(|error| error.to_string())?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

pub fn extract_zip(zip_path: &Path, target: &Path) -> Result<(), String> {
    let file = fs::File::open(zip_path).map_err(|error| error.to_string())?;
    let mut archive = zip::ZipArchive::new(file).map_err(|error| error.to_string())?;
    fs::create_dir_all(target).map_err(|error| error.to_string())?;
    for index in 0..archive.len() {
        let mut entry = archive
            .by_index(index)
            .map_err(|error| format!("повреждённый архив: {error}"))?;
        let Some(relative) = entry.enclosed_name() else {
            continue;
        };
        let path = target.join(relative);
        if entry.is_dir() {
            fs::create_dir_all(&path).map_err(|error| error.to_string())?;
            continue;
        }
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        }
        let mut out = fs::File::create(&path).map_err(|error| error.to_string())?;
        std::io::copy(&mut entry, &mut out).map_err(|error| error.to_string())?;
        #[cfg(unix)]
        if let Some(mode) = entry.unix_mode() {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&path, fs::Permissions::from_mode(mode));
        }
    }
    Ok(())
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct DownloadState {
    pub phase: String,
    pub downloaded: u64,
    pub total: u64,
    pub message: String,
    pub error: String,
    pub running: bool,
    pub install_dir: String,
    pub mode: String,
    #[serde(rename = "engineZip")]
    pub engine_zip: String,
    #[serde(rename = "contentZip")]
    pub content_zip: String,
    #[serde(rename = "engineSig")]
    pub engine_sig: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub info: Option<ServerInfo>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct DownloadSpec {
    #[serde(default, rename = "server_url")]
    pub server_url: String,
    #[serde(default, rename = "install_dir")]
    pub install_dir: String,
}

struct Job {
    state: Mutex<DownloadState>,
}

static JOB: OnceLock<Job> = OnceLock::new();

fn job() -> &'static Job {
    JOB.get_or_init(|| Job {
        state: Mutex::new(DownloadState {
            phase: "idle".into(),
            running: false,
            ..DownloadState::default()
        }),
    })
}

fn set_state(patch: impl FnOnce(&mut DownloadState)) {
    if let Ok(mut state) = job().state.lock() {
        patch(&mut state);
    }
}

pub fn snapshot() -> DownloadState {
    job()
        .state
        .lock()
        .map(|state| state.clone())
        .unwrap_or_default()
}

pub fn start_download(spec: DownloadSpec) -> Result<(), String> {
    let server_url = spec.server_url.trim().to_string();
    if server_url.is_empty() {
        return Err("не указан адрес сервера".into());
    }
    let install_dir = spec.install_dir.trim().to_string();
    let mut state = job().state.lock().map_err(|_| "загрузчик недоступен")?;
    if state.running {
        return Err("загрузка уже идёт".into());
    }
    state.phase = "info".into();
    state.message = String::new();
    state.error = String::new();
    state.downloaded = 0;
    state.total = 0;
    state.install_dir = String::new();
    state.info = None;
    state.running = true;
    drop(state);
    thread::spawn(move || run_job(server_url, install_dir));
    Ok(())
}

fn run_job(server_url: String, install_dir_raw: String) {
    match execute(&server_url, &install_dir_raw) {
        Ok((target, info, message)) => set_state(|state| {
            state.phase = "done".into();
            state.message = message;
            state.install_dir = target.display().to_string();
            state.info = Some(info);
            state.running = false;
        }),
        Err(message) => set_state(|state| {
            state.phase = "error".into();
            state.error = message;
            state.running = false;
        }),
    }
}

fn execute(
    server_url: &str,
    install_dir_raw: &str,
) -> Result<(PathBuf, ServerInfo, String), String> {
    let info = fetch_info(server_url)?;
    let build = info.build.clone();

    let root = resolve_install_root(install_dir_raw)?;
    fs::create_dir_all(&root).map_err(|error| error.to_string())?;
    let fork = build.fork_id.trim();
    let target = if fork.is_empty() {
        root.join("client")
    } else {
        root.join(sanitize_component(fork))
    };

    set_state(|state| {
        state.phase = "info".into();
        state.message = format!("сборка {} для {}", build.version, platform_name());
    });

    let stored = read_marker(&target);
    if let Some(stored) = stored.as_ref() {
        if build_matches(stored, &build) {
            return Ok((target, info, "клиент уже актуален".into()));
        }
    }

    let use_acz = build.acz
        && !build.manifest_url.trim().is_empty()
        && !build.manifest_download_url.trim().is_empty();
    if use_acz {
        match run_acz(&build, &root, &target) {
            Ok(payload) => {
                write_marker(
                    &target,
                    &StoredBuild {
                        version: build.version.clone(),
                        fork_id: build.fork_id.clone(),
                        hash: build.hash.clone(),
                        manifest_hash: payload.manifest_hash.clone(),
                        engine_version: build.engine_version.clone(),
                        acz: true,
                    },
                )?;
                set_state(|state| {
                    state.mode = "acz".into();
                    state.engine_zip = payload.engine_zip.display().to_string();
                    state.content_zip = payload.content_zip.display().to_string();
                    state.engine_sig = payload.engine_sig.clone();
                });
                return Ok((target, info, payload.message));
            }
            Err(acz_error) => {
                if build.download_url.trim().is_empty() {
                    return Err(acz_error);
                }
                let zip_result = run_zip(&build, &root, &target);
                match zip_result {
                    Ok(message) => {
                        write_marker(
                            &target,
                            &StoredBuild {
                                version: build.version.clone(),
                                fork_id: build.fork_id.clone(),
                                hash: build.hash.clone(),
                                acz: false,
                                ..StoredBuild::default()
                            },
                        )?;
                        set_state(|state| {
                            state.mode = "zip".into();
                        });
                        return Ok((target, info, message));
                    }
                    Err(zip_error) => {
                        return Err(format!(
                            "{acz_error}; загрузка zip тоже не удалась: {zip_error}"
                        ));
                    }
                }
            }
        }
    }

    let message = run_zip(&build, &root, &target)?;
    write_marker(
        &target,
        &StoredBuild {
            version: build.version.clone(),
            fork_id: build.fork_id.clone(),
            hash: build.hash.clone(),
            acz: false,
            ..StoredBuild::default()
        },
    )?;
    set_state(|state| {
        state.mode = "zip".into();
    });
    Ok((target, info, message))
}

struct AczPayload {
    manifest_hash: String,
    engine_zip: PathBuf,
    content_zip: PathBuf,
    engine_sig: String,
    message: String,
}

fn run_acz(build: &ServerBuild, root: &Path, target: &Path) -> Result<AczPayload, String> {
    let engine_version = build.engine_version.trim();
    if engine_version.is_empty() {
        return Err("сервер не указал версию движка".into());
    }

    set_state(|state| {
        state.phase = "engine".into();
        state.message = format!("получаем движок {engine_version}");
        state.downloaded = 0;
        state.total = 0;
    });
    let manifest = engine::fetch_engine_manifest()?;
    let (resolved_version, rid, platform) = engine::find_engine(&manifest, engine_version)?;
    let engine_root = root.join("engine");
    fs::create_dir_all(&engine_root).map_err(|error| error.to_string())?;
    let engine_zip = engine::engine_cache_path(&engine_root, &resolved_version, rid);
    let engine_fresh = engine::verify_engine_zip(&engine_zip, &platform.sha256)?;
    if !engine_fresh {
        let temp_name = engine_zip
            .file_name()
            .map(|name| name.to_string_lossy().to_string())
            .unwrap_or_else(|| "engine.zip".into());
        let engine_temp = engine_root.join(format!("{temp_name}.tmp"));
        set_state(|state| {
            state.phase = "engine".into();
            state.message = format!("загружаем движок {resolved_version}");
            state.downloaded = 0;
            state.total = 0;
        });
        download_to(&platform.url, &engine_temp)?;
        let digest = sha256_file(&engine_temp)?;
        if !digest.eq_ignore_ascii_case(platform.sha256.trim()) {
            fs::remove_file(&engine_temp).ok();
            return Err("хэш движка не совпал".into());
        }
        fs::rename(&engine_temp, &engine_zip).map_err(|error| error.to_string())?;
    }
    let engine_sig = platform.sig.trim().to_string();
    if engine_sig.is_empty() {
        return Err("у сборки движка нет подписи".into());
    }

    set_state(|state| {
        state.phase = "download".into();
        state.message = "читаем манифест контента".into();
        state.downloaded = 0;
        state.total = 0;
    });
    let (entries, manifest_hash) = acz::fetch_manifest(&build.manifest_url)?;
    let server_manifest_hash = build.manifest_hash.trim().to_ascii_lowercase();
    if !server_manifest_hash.is_empty()
        && !manifest_hash.eq_ignore_ascii_case(&server_manifest_hash)
    {
        return Err("хэш манифеста контента не совпал".into());
    }

    let fork_name = acz::sanitize_dir_name(&build.fork_id);
    let blobs = acz::blobs_dir(&cache_root()?, &fork_name);
    let missing: Vec<acz::ManifestEntry> = acz::unique_entries(&entries)
        .into_iter()
        .filter(|entry| {
            let path = blobs.join(format!("{}.bin", entry.hash_hex));
            !fs::metadata(&path)
                .map(|meta| meta.len() > 0)
                .unwrap_or(false)
        })
        .collect();
    let total_unique = acz::unique_entries(&entries).len();
    let fresh = total_unique - missing.len();

    if !missing.is_empty() {
        let client = download_client()?;
        let mut done_files = fresh as u64;
        acz::check_download_protocol(&client, &build.manifest_download_url)?;
        set_state(|state| {
            state.phase = "download".into();
            state.message = "загружаем файлы сборки".into();
            state.downloaded = 0;
            state.total = 0;
        });
        acz::download_blobs(&client, &build.manifest_download_url, &missing, |blob| {
            acz::write_blob_cache(&blobs, &blob.hash_hex, &blob.data)?;
            done_files += 1;
            let current_files = done_files;
            set_state(|state| {
                state.downloaded = current_files;
                state.total = total_unique as u64;
                state.message = format!("загружаем файлы {current_files}/{total_unique}");
            });
            Ok(())
        })?;
    } else {
        set_state(|state| {
            state.phase = "download".into();
            state.downloaded = total_unique as u64;
            state.total = total_unique as u64;
            state.message = "все файлы уже в кэше".into();
        });
    }

    set_state(|state| {
        state.phase = "extract".into();
        state.message = "собираем клиент".into();
        state.downloaded = 0;
        state.total = 0;
    });
    fs::create_dir_all(target).map_err(|error| error.to_string())?;
    let content_zip = target.join("content.zip");
    acz::assemble_overlay_zip(&entries, &blobs, &content_zip, |done| {
        set_state(|state| state.downloaded = done);
    })?;

    Ok(AczPayload {
        manifest_hash,
        engine_zip,
        content_zip,
        engine_sig,
        message: "клиент готов".into(),
    })
}

fn cache_root() -> Result<PathBuf, String> {
    dirs::cache_dir()
        .map(|dir| dir.join("illusio"))
        .ok_or_else(|| "не удалось определить каталог кэша".into())
}

fn run_zip(build: &ServerBuild, root: &Path, target: &Path) -> Result<String, String> {
    if build.download_url.trim().is_empty() {
        return Err("сервер не даёт ссылку на загрузку клиента".into());
    }
    let temp_file = root.join(format!("illusio-{}.zip.tmp", std::process::id()));
    let candidates = zip_candidates(build);
    if candidates.is_empty() {
        return Err("сервер не даёт ссылку на загрузку клиента".into());
    }

    let mut last_error = String::new();
    let mut downloaded_path: Option<PathBuf> = None;
    for candidate in &candidates {
        set_state(|state| {
            state.phase = "download".into();
            state.downloaded = 0;
            state.total = 0;
            state.message = "загружаем клиент".into();
        });
        match download_to(candidate, &temp_file) {
            Ok(()) => {
                downloaded_path = Some(temp_file.clone());
                break;
            }
            Err(message) => {
                last_error = message;
                fs::remove_file(&temp_file).ok();
            }
        }
    }
    let Some(zip_path) = downloaded_path else {
        return Err(format!("не удалось скачать клиент: {last_error}"));
    };

    if !build.hash.trim().is_empty() {
        set_state(|state| {
            state.phase = "extract".into();
            state.message = "проверяем подпись сборки".into();
        });
        let actual = sha256_file(&zip_path)?;
        let expected = build.hash.trim().to_ascii_lowercase();
        if !actual.eq_ignore_ascii_case(&expected) {
            fs::remove_file(&zip_path).ok();
            return Err("хэш сборки не совпал, файл повреждён".into());
        }
    }

    set_state(|state| {
        state.phase = "extract".into();
        state.message = "распаковываем".into();
    });

    if target.exists() {
        fs::remove_dir_all(target).map_err(|error| error.to_string())?;
    }
    extract_zip(&zip_path, target)?;
    fs::remove_file(&zip_path).ok();

    Ok("клиент готов".into())
}

fn sanitize_component(value: &str) -> String {
    let cleaned: String = value
        .trim()
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.' {
                c
            } else {
                '_'
            }
        })
        .collect();
    if cleaned.is_empty() {
        "client".into()
    } else {
        cleaned
    }
}

fn download_client() -> Result<reqwest::blocking::Client, String> {
    reqwest::blocking::Client::builder()
        .timeout(None)
        .connect_timeout(DOWNLOAD_TIMEOUT)
        .build()
        .map_err(|error| error.to_string())
}

fn download_to(url: &str, path: &Path) -> Result<(), String> {
    let client = download_client()?;
    let response = client.get(url).send().map_err(|error| error.to_string())?;
    if response.status().as_u16() == 404 {
        return Err(format!("файл не найден: {url}"));
    }
    let mut response = response
        .error_for_status()
        .map_err(|error| error.to_string())?;
    let total = response.content_length().unwrap_or(0);
    set_state(|state| state.total = total);

    let mut file = fs::File::create(path).map_err(|error| error.to_string())?;
    let mut buffer = [0u8; 65536];
    let mut downloaded: u64 = 0;
    let mut last_report: u64 = 0;
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
        if downloaded - last_report >= 262_144 || read < buffer.len() {
            last_report = downloaded;
            let current = downloaded;
            set_state(|state| {
                state.downloaded = current;
                state.total = if total > 0 { total } else { current };
            });
        }
    }
    file.flush().map_err(|error| error.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_build(download_url: &str, version: &str) -> ServerBuild {
        ServerBuild {
            download_url: download_url.into(),
            version: version.into(),
            ..ServerBuild::default()
        }
    }

    #[test]
    fn builds_info_url() {
        assert_eq!(info_url("example.com"), "example.com/info");
        assert_eq!(info_url("example.com/"), "example.com/info");
    }

    #[test]
    fn composes_zip_candidates() {
        let build = sample_build("https://cdn.example.com/builds", "240.1");
        assert_eq!(
            zip_candidates(&build),
            vec![
                "https://cdn.example.com/builds/240.1/linux.zip".to_string(),
                "https://cdn.example.com/builds/linux.zip".to_string(),
            ]
        );
        let no_version = sample_build("https://cdn.example.com/builds", "");
        assert_eq!(
            zip_candidates(&no_version),
            vec!["https://cdn.example.com/builds/linux.zip".to_string()]
        );
        let direct = sample_build("https://cdn.example.com/client.zip", "");
        assert_eq!(
            zip_candidates(&direct),
            vec!["https://cdn.example.com/client.zip".to_string()]
        );
        let empty = sample_build("", "");
        assert!(zip_candidates(&empty).is_empty());
    }

    #[test]
    fn sanitizes_fork_names() {
        assert_eq!(
            sanitize_component(" forks/..space_wizards "),
            "forks_..space_wizards"
        );
        assert_eq!(sanitize_component("///"), "___");
        assert_eq!(sanitize_component("   "), "client");
    }

    #[test]
    fn marker_roundtrip() {
        let dir = std::env::temp_dir().join(format!("illusio-marker-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let build = StoredBuild {
            version: "240.1".into(),
            fork_id: "space_wizards".into(),
            hash: "abcd".into(),
            manifest_hash: "feed".into(),
            engine_version: "240.1.0.5".into(),
            acz: true,
        };
        write_marker(&dir, &build).unwrap();
        let read = read_marker(&dir).unwrap();
        assert_eq!(read.version, "240.1");
        assert_eq!(read.hash, "abcd");
        assert_eq!(read.manifest_hash, "feed");
        assert_eq!(read.engine_version, "240.1.0.5");
        assert!(read.acz);
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn matches_by_hash_then_version() {
        let mut build = ServerBuild {
            hash: " AAA ".into(),
            version: "1".into(),
            ..ServerBuild::default()
        };
        let stored = StoredBuild {
            version: "1".into(),
            fork_id: String::new(),
            hash: "aaa".into(),
            ..StoredBuild::default()
        };
        assert!(build_matches(&stored, &build));
        build.hash = "bbb".into();
        assert!(!build_matches(&stored, &build));
        build.hash = String::new();
        assert!(build_matches(&stored, &build));
        build.version = "2".into();
        assert!(!build_matches(&stored, &build));
    }

    #[test]
    fn hashes_known_bytes() {
        let dir = std::env::temp_dir().join(format!("illusio-hash-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("data.bin");
        fs::write(&path, b"abc").unwrap();
        let digest = sha256_file(&path).unwrap();
        assert_eq!(
            digest,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn extracts_and_keeps_permissions() {
        let dir = std::env::temp_dir().join(format!("illusio-zip-{}", std::process::id()));
        let target = dir.join("out");
        fs::create_dir_all(&dir).unwrap();
        let zip_path = dir.join("client.zip");
        let file = fs::File::create(&zip_path).unwrap();
        let mut writer = zip::ZipWriter::new(file);
        let options = zip::write::SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated)
            .unix_permissions(0o755);
        writer.start_file("Robust.Client", options).unwrap();
        writer.write_all(b"binary").unwrap();
        writer
            .start_file("data/config.txt", zip::write::SimpleFileOptions::default())
            .unwrap();
        writer.write_all(b"hello").unwrap();
        writer.finish().unwrap();
        extract_zip(&zip_path, &target).unwrap();
        assert!(target.join("Robust.Client").exists());
        assert!(target.join("data/config.txt").exists());
        fs::remove_dir_all(&dir).ok();
    }
}

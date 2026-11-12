use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::io::{Read, Write};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::Duration;

use crate::acz;
use crate::engine;

const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(20);
const DOWNLOAD_MAX_TIME: Duration = Duration::from_secs(10_800);
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
    #[serde(default)]
    pub links: Vec<ServerLink>,
    #[serde(default, rename = "privacy_policy")]
    pub privacy_policy: Option<ServerPrivacy>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ServerLink {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub icon: String,
    #[serde(default)]
    pub url: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ServerPrivacy {
    #[serde(default)]
    pub link: String,
    #[serde(default)]
    pub identifier: String,
    #[serde(default)]
    pub version: String,
}

pub fn info_url(server_url: &str) -> String {
    format!("{}/info", server_url.trim_end_matches('/'))
}

fn status_client() -> Result<reqwest::blocking::Client, String> {
    crate::http::with_route(
        reqwest::blocking::Client::builder(),
        crate::http::Route::Launcher,
    )
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
    #[serde(default, rename = "engineZip")]
    pub engine_zip: String,
    #[serde(default, rename = "engineSig")]
    pub engine_sig: String,
    #[serde(default, rename = "manifestUrl")]
    pub manifest_url: String,
    #[serde(default, rename = "manifestDownloadUrl")]
    pub manifest_download_url: String,
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
    let temp = dir.join("version.tmp");
    fs::write(&temp, raw).map_err(|error| error.to_string())?;
    fs::rename(&temp, marker_path(dir)).map_err(|error| error.to_string())
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
    #[serde(rename = "modules", skip_serializing_if = "Vec::is_empty", default)]
    pub modules: Vec<String>,
    #[serde(
        rename = "bundleZip",
        skip_serializing_if = "String::is_empty",
        default
    )]
    pub bundle_zip: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub info: Option<ServerInfo>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct DownloadSpec {
    #[serde(default, rename = "server_url")]
    pub server_url: String,
    #[serde(default, rename = "install_dir")]
    pub install_dir: String,
    #[serde(default, rename = "bundle_zip")]
    pub bundle_zip: String,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct BundleInfo {
    #[serde(rename = "engineVersion")]
    pub engine_version: String,
    #[serde(rename = "baseBuild")]
    pub base_build: ServerBuild,
    #[serde(rename = "bundleZip")]
    pub bundle_zip: String,
    #[serde(rename = "fullBuild")]
    pub full_build: bool,
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
    let mut state = job()
        .state
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    patch(&mut state);
}

pub fn snapshot() -> DownloadState {
    job()
        .state
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .clone()
}

static DOWNLOAD_CANCEL: AtomicBool = AtomicBool::new(false);

pub fn download_cancel() {
    DOWNLOAD_CANCEL.store(true, Ordering::SeqCst);
}

fn download_cancelled() -> bool {
    DOWNLOAD_CANCEL.load(Ordering::SeqCst)
}

struct JobGuard {
    armed: bool,
}

impl Default for JobGuard {
    fn default() -> Self {
        Self { armed: true }
    }
}

impl JobGuard {
    fn disarm(mut self) {
        self.armed = false;
    }
}

impl Drop for JobGuard {
    fn drop(&mut self) {
        if self.armed {
            set_state(|state| {
                state.running = false;
                state.phase = "error".into();
                if state.error.is_empty() {
                    state.error = "задание прервано внутренней ошибкой ядра".into();
                }
            });
        }
    }
}

pub fn start_download(spec: DownloadSpec) -> Result<(), String> {
    let bundle_zip = spec.bundle_zip.trim().to_string();
    let server_url = spec.server_url.trim().to_string();
    if server_url.is_empty() && bundle_zip.is_empty() {
        return Err("не указан адрес сервера".into());
    }
    let install_dir = spec.install_dir.trim().to_string();
    let mut state = job()
        .state
        .lock()
        .unwrap_or_else(|error| error.into_inner());
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
    state.bundle_zip = String::new();
    state.mode = String::new();
    state.engine_zip = String::new();
    state.content_zip = String::new();
    state.engine_sig = String::new();
    state.running = true;
    drop(state);
    DOWNLOAD_CANCEL.store(false, Ordering::SeqCst);
    thread::spawn(move || {
        let guard = JobGuard::default();
        let spec = DownloadSpec {
            server_url,
            install_dir,
            bundle_zip,
        };
        let result = catch_unwind(AssertUnwindSafe(|| run_job(spec)));
        if result.is_err() {
            set_state(|state| {
                state.running = false;
                state.phase = "error".into();
                state.error = "загрузка прервана внутренней ошибкой ядра".into();
            });
        }
        guard.disarm();
    });
    Ok(())
}

pub fn content_state(server_url: &str, install_dir_raw: &str) -> Result<bool, String> {
    let info = fetch_info(server_url)?;
    let build = info.build.clone();
    let root = resolve_install_root(install_dir_raw)?;
    let fork = build.fork_id.trim();
    let target = if fork.is_empty() {
        root.join("client")
    } else {
        root.join(sanitize_component(fork))
    };
    let stored = read_marker(&target);
    Ok(match stored {
        Some(stored) => build_matches(&stored, &build),
        None => false,
    })
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct VerifySpec {
    #[serde(default, rename = "server_url")]
    pub server_url: String,
    #[serde(default, rename = "install_dir")]
    pub install_dir: String,
}

pub fn start_verify(spec: VerifySpec) -> Result<(), String> {
    let server_url = spec.server_url.trim().to_string();
    let install_dir = spec.install_dir.trim().to_string();
    let mut state = job()
        .state
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    if state.running {
        return Err("загрузка уже идёт".into());
    }
    state.phase = "verify".into();
    state.message = String::new();
    state.error = String::new();
    state.downloaded = 0;
    state.total = 0;
    state.install_dir = install_dir.clone();
    state.info = None;
    state.bundle_zip = String::new();
    state.mode = String::new();
    state.engine_zip = String::new();
    state.content_zip = String::new();
    state.engine_sig = String::new();
    state.running = true;
    drop(state);
    DOWNLOAD_CANCEL.store(false, Ordering::SeqCst);
    thread::spawn(move || {
        let guard = JobGuard::default();
        let spec = VerifySpec {
            server_url,
            install_dir,
        };
        let result = catch_unwind(AssertUnwindSafe(|| run_verify(spec)));
        if result.is_err() {
            set_state(|state| {
                state.running = false;
                state.phase = "error".into();
                state.error = "проверка прервана внутренней ошибкой ядра".into();
            });
        }
        guard.disarm();
    });
    Ok(())
}

fn run_verify(spec: VerifySpec) {
    match verify_job(&spec) {
        Ok(message) => set_state(|state| {
            state.phase = "done".into();
            state.message = message;
            state.running = false;
        }),
        Err(message) => set_state(|state| {
            state.phase = "error".into();
            state.error = message;
            state.running = false;
        }),
    }
}

fn find_installed_marker(root: &Path) -> Result<(PathBuf, StoredBuild), String> {
    let entries = fs::read_dir(root).map_err(|error| error.to_string())?;
    let mut best: Option<(PathBuf, StoredBuild)> = None;
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let name = path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("");
        if matches!(name, "engine" | "bundles" | "logs" | "tools") {
            continue;
        }
        let Some(stored) = read_marker(&path) else {
            continue;
        };
        let replace = match best.as_ref() {
            None => true,
            Some((_, current)) => stored.acz && !current.acz,
        };
        if replace {
            best = Some((path, stored));
        }
    }
    best.ok_or_else(|| "установка не найдена: сначала подключитесь к серверу".into())
}

fn verify_job(spec: &VerifySpec) -> Result<String, String> {
    let install_dir_raw = spec.install_dir.trim();
    if install_dir_raw.is_empty() {
        return Err("не указан каталог установки".into());
    }
    set_state(|state| {
        state.message = "ищем установленную сборку".into();
    });
    let root = resolve_install_root(install_dir_raw)?;
    let (target, stored) = find_installed_marker(&root)?;

    if !stored.acz {
        return Ok(
            "установка из zip: целостность подтверждает маркер сборки, проверять нечего".into(),
        );
    }

    let mut build: Option<ServerBuild> = None;
    let server_url = spec.server_url.trim();
    if !server_url.is_empty() {
        set_state(|state| {
            state.message = "получаем данные сервера".into();
        });
        let info = fetch_info(server_url)?;
        build = Some(info.build.clone());
    }

    let manifest_url = if !stored.manifest_url.trim().is_empty() {
        stored.manifest_url.trim().to_string()
    } else {
        match build.as_ref().map(|value| value.manifest_url.trim()) {
            Some(url) if !url.is_empty() => url.to_string(),
            _ => {
                return Err(
                    "в маркере нет адреса манифеста: подключитесь к серверу этой сборки и повторите"
                        .into(),
                );
            }
        }
    };
    let manifest_download_url = if !stored.manifest_download_url.trim().is_empty() {
        stored.manifest_download_url.trim().to_string()
    } else {
        match build
            .as_ref()
            .map(|value| value.manifest_download_url.trim())
        {
            Some(url) if !url.is_empty() => url.to_string(),
            _ => {
                return Err(
                    "в маркере нет адреса загрузки: подключитесь к серверу этой сборки и повторите"
                        .into(),
                );
            }
        }
    };

    let expected_hash = if !stored.manifest_hash.trim().is_empty() {
        stored.manifest_hash.trim().to_string()
    } else {
        build
            .as_ref()
            .map(|value| value.manifest_hash.trim().to_string())
            .unwrap_or_default()
    };

    set_state(|state| {
        state.message = "читаем манифест контента".into();
    });
    let (entries, manifest_hash) = acz::fetch_manifest(&manifest_url)?;
    if !expected_hash.is_empty() && !manifest_hash.eq_ignore_ascii_case(&expected_hash) {
        return Err("манифест на сервере изменился — подключитесь к серверу для обновления".into());
    }

    let fork_name = acz::sanitize_dir_name(&stored.fork_id);
    let blobs = acz::blobs_dir(&cache_root()?, &fork_name);
    let unique = acz::unique_entries(&entries);
    let total = unique.len();

    set_state(|state| {
        state.downloaded = 0;
        state.total = total as u64;
        state.message = format!("проверяем файлы 0/{total}");
    });
    let mut broken: Vec<acz::ManifestEntry> = Vec::new();
    for (checked, entry) in unique.iter().enumerate() {
        if !blob_healthy(&blobs, &entry.hash_hex) {
            broken.push(entry.clone());
        }
        if (checked + 1) % 32 == 0 || checked + 1 == total {
            let done = checked + 1;
            set_state(|state| {
                state.downloaded = done as u64;
                state.message = format!("проверяем файлы {done}/{total}");
            });
        }
    }

    if broken.is_empty() {
        return Ok(format!("все файлы целы ({total})"));
    }

    let broken_total = broken.len();
    set_state(|state| {
        state.downloaded = 0;
        state.total = broken_total as u64;
        state.phase = "verify".into();
        state.message = format!("повреждено или отсутствует {broken_total} из {total}");
    });
    let client = download_client()?;
    acz::check_download_protocol(&client, &manifest_download_url)?;
    let mut done: u64 = 0;
    acz::download_blobs(&client, &manifest_download_url, &broken, |blob| {
        acz::write_blob_cache(&blobs, &blob.hash_hex, &blob.data)?;
        done += 1;
        let current = done;
        set_state(|state| {
            state.downloaded = current;
            state.message = format!("докачиваем файлы {current}/{broken_total}");
        });
        Ok(())
    })?;

    let assemble_total = blob_bytes(&blobs, &entries);
    set_state(|state| {
        state.downloaded = 0;
        state.total = assemble_total;
        state.message = "собираем клиент".into();
    });
    fs::create_dir_all(&target).map_err(|error| error.to_string())?;
    let content_zip = target.join("content.zip");
    acz::assemble_overlay_zip(&entries, &blobs, &content_zip, |finished| {
        let total = assemble_total;
        set_state(|state| state.downloaded = finished.min(total));
    })?;

    Ok(format!("исправлено {broken_total} из {total} файлов"))
}

fn run_job(spec: DownloadSpec) {
    let result = if spec.bundle_zip.trim().is_empty() {
        execute(&spec.server_url, &spec.install_dir)
            .map(|(target, info, message)| (target, info, message, String::new()))
    } else {
        execute_bundle(&spec)
    };
    match result {
        Ok((target, info, message, bundle)) => {
            let report = crate::config::load()
                .and_then(|config| crate::cull::cull(&config))
                .ok();
            let cull_note = match report {
                Some(value) if value.files > 0 => format!(
                    " · очищено {} файлов ({:.1} МБ)",
                    value.files,
                    value.bytes as f64 / 1_048_576.0
                ),
                _ => String::new(),
            };
            set_state(|state| {
                state.phase = "done".into();
                state.message = format!("{message}{cull_note}");
                state.install_dir = target.display().to_string();
                state.info = Some(info);
                state.bundle_zip = bundle;
                state.running = false;
            })
        }
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
            if !stored.acz {
                set_state(|state| {
                    state.mode = "zip".into();
                });
                return Ok((target, info, "клиент уже актуален".into()));
            }
            let content_zip = target.join("content.zip");
            if content_zip.exists() {
                let cached_engine = PathBuf::from(stored.engine_zip.trim());
                let pair = if !stored.engine_zip.trim().is_empty()
                    && !stored.engine_sig.trim().is_empty()
                    && cached_engine.exists()
                {
                    Some((cached_engine, stored.engine_sig.clone()))
                } else {
                    prepare_engine(&root, &stored.engine_version).ok()
                };
                if let Some((engine_zip, engine_sig)) = pair {
                    set_state(|state| {
                        state.mode = "acz".into();
                        state.engine_zip = engine_zip.display().to_string();
                        state.content_zip = content_zip.display().to_string();
                        state.engine_sig = engine_sig.clone();
                        state.modules = crate::modules::read_names(&engine_zip).unwrap_or_default();
                    });
                    return Ok((target, info, "клиент уже актуален".into()));
                }
            }
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
                        engine_zip: payload.engine_zip.display().to_string(),
                        engine_sig: payload.engine_sig.clone(),
                        manifest_url: build.manifest_url.clone(),
                        manifest_download_url: build.manifest_download_url.clone(),
                    },
                )?;
                set_state(|state| {
                    state.mode = "acz".into();
                    state.engine_zip = payload.engine_zip.display().to_string();
                    state.content_zip = payload.content_zip.display().to_string();
                    state.engine_sig = payload.engine_sig.clone();
                    state.modules =
                        crate::modules::read_names(&payload.engine_zip).unwrap_or_default();
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

fn prepare_engine(root: &Path, engine_version: &str) -> Result<(PathBuf, String), String> {
    let version = engine_version.trim();
    if version.is_empty() {
        return Err("не указана версия движка".into());
    }
    set_state(|state| {
        state.phase = "engine".into();
        state.message = format!("получаем движок {version}");
        state.downloaded = 0;
        state.total = 0;
    });
    let manifest = engine::fetch_engine_manifest()?;
    let (resolved_version, rid, platform) = engine::find_engine(&manifest, version)?;
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
            fs::remove_file(sidecar_path(&engine_temp)).ok();
            return Err("хэш движка не совпал".into());
        }
        fs::rename(&engine_temp, &engine_zip).map_err(|error| error.to_string())?;
        fs::remove_file(sidecar_path(&engine_temp)).ok();
    }
    let engine_sig = platform.sig.trim().to_string();
    if engine_sig.is_empty() {
        return Err("у сборки движка нет подписи".into());
    }
    Ok((engine_zip, engine_sig))
}

#[derive(Debug, Deserialize)]
pub struct BundleMeta {
    #[serde(default, rename = "engine_version")]
    engine_version: String,
    #[serde(default, rename = "base_build")]
    base_build: ServerBuild,
}

pub fn read_bundle_meta(zip_path: &Path) -> Result<(BundleMeta, bool), String> {
    let file = fs::File::open(zip_path).map_err(|error| error.to_string())?;
    let mut archive = zip::ZipArchive::new(file).map_err(|error| error.to_string())?;
    let mut has_manifest = false;
    let mut meta: Option<BundleMeta> = None;
    for index in 0..archive.len() {
        let name = archive.name_for_index(index).unwrap_or("").to_string();
        if name == "manifest.yml" {
            has_manifest = true;
        }
        if name == "rt_content_bundle.json" {
            let mut entry = archive
                .by_index(index)
                .map_err(|error| format!("повреждённый архив: {error}"))?;
            let mut raw = String::new();
            entry
                .read_to_string(&mut raw)
                .map_err(|error| error.to_string())?;
            meta = Some(
                serde_json::from_str::<BundleMeta>(&raw)
                    .map_err(|error| format!("некорректный rt_content_bundle.json: {error}"))?,
            );
        }
    }
    match meta {
        Some(meta) => Ok((meta, has_manifest)),
        None => Err("в архиве нет rt_content_bundle.json: это не реплей content bundle".into()),
    }
}

fn download_content_zip(build: &ServerBuild, root: &Path) -> Result<PathBuf, String> {
    let candidates = zip_candidates(build);
    if candidates.is_empty() {
        return Err("в base_build нет ссылки на загрузку клиента".into());
    }
    let mut folder_name = sanitize_component(&build.fork_id);
    if folder_name == "client" {
        folder_name = "bundle-base".into();
    }
    let dir = root.join("bundles").join(folder_name);
    fs::create_dir_all(&dir).map_err(|error| error.to_string())?;
    let hash_part = build.hash.trim().to_ascii_lowercase();
    let hash_hex = if is_sha256_hex(&hash_part) {
        hash_part
    } else {
        String::new()
    };
    let name_part = if hash_hex.is_empty() {
        sanitize_component(&build.version)
    } else {
        format!(
            "{}-{}",
            sanitize_component(&build.version),
            hash_prefix(&hash_hex, 8)
        )
    };
    let target = dir.join(format!("{name_part}.zip"));
    if fs::metadata(&target)
        .map(|meta| meta.len() > 0)
        .unwrap_or(false)
        && (hash_hex.is_empty() || sha256_file(&target)?.eq_ignore_ascii_case(&hash_hex))
    {
        return Ok(target);
    }
    let temp_file = dir.join(format!("illusio-{}.zip.tmp", std::process::id()));
    let mut last_error = String::new();
    let mut downloaded = false;
    for candidate in &candidates {
        if download_cancelled() {
            return Err("загрузка отменена".into());
        }
        set_state(|state| {
            state.phase = "download".into();
            state.downloaded = 0;
            state.total = 0;
            state.message = "загружаем базовую сборку бандла".into();
        });
        match download_to(candidate, &temp_file) {
            Ok(()) => {
                downloaded = true;
                break;
            }
            Err(message) => {
                last_error = message;
                if download_cancelled() {
                    return Err(last_error);
                }
            }
        }
    }
    if !downloaded {
        return Err(format!("не удалось скачать базовую сборку: {last_error}"));
    }
    if !hash_hex.is_empty() {
        let actual = sha256_file(&temp_file)?;
        if !actual.eq_ignore_ascii_case(&hash_hex) {
            fs::remove_file(&temp_file).ok();
            fs::remove_file(sidecar_path(&temp_file)).ok();
            return Err("хэш базовой сборки не совпал".into());
        }
    }
    fs::rename(&temp_file, &target).map_err(|error| error.to_string())?;
    fs::remove_file(sidecar_path(&temp_file)).ok();
    Ok(target)
}

fn execute_bundle(spec: &DownloadSpec) -> Result<(PathBuf, ServerInfo, String, String), String> {
    let bundle_zip = PathBuf::from(spec.bundle_zip.trim());
    if !bundle_zip.exists() {
        return Err("файл бандла не найден".into());
    }
    let (meta, has_manifest) = read_bundle_meta(&bundle_zip)?;
    let root = resolve_install_root(&spec.install_dir)?;
    fs::create_dir_all(&root).map_err(|error| error.to_string())?;

    let engine_version = if meta.engine_version.trim().is_empty() {
        meta.base_build.engine_version.clone()
    } else {
        meta.engine_version.clone()
    };
    let (engine_zip, engine_sig) = prepare_engine(&root, &engine_version)?;

    let content_zip = if has_manifest {
        bundle_zip.clone()
    } else {
        download_content_zip(&meta.base_build, &root)?
    };

    let target = root.join("bundle");
    fs::create_dir_all(&target).map_err(|error| error.to_string())?;
    let info = ServerInfo {
        connect_address: String::new(),
        build: ServerBuild {
            version: meta.base_build.version.clone(),
            fork_id: meta.base_build.fork_id.clone(),
            engine_version,
            hash: meta.base_build.hash.clone(),
            manifest_hash: meta.base_build.manifest_hash.clone(),
            ..ServerBuild::default()
        },
        ..ServerInfo::default()
    };
    let bundle_path = if has_manifest {
        String::new()
    } else {
        bundle_zip.display().to_string()
    };
    set_state(|state| {
        state.mode = "acz".into();
        state.engine_zip = engine_zip.display().to_string();
        state.content_zip = content_zip.display().to_string();
        state.engine_sig = engine_sig;
        state.modules = crate::modules::read_names(&engine_zip).unwrap_or_default();
        state.message = "реплей готов к запуску".into();
    });
    Ok((target, info, "content bundle готов".into(), bundle_path))
}

fn run_acz(build: &ServerBuild, root: &Path, target: &Path) -> Result<AczPayload, String> {
    let engine_version = build.engine_version.trim();
    if engine_version.is_empty() {
        return Err("сервер не указал версию движка".into());
    }
    let (engine_zip, engine_sig) = prepare_engine(root, engine_version)?;

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
        .filter(|entry| !blob_healthy(&blobs, &entry.hash_hex))
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

    let assemble_bytes = blob_bytes(&blobs, &entries);
    set_state(|state| {
        state.phase = "extract".into();
        state.message = "собираем клиент".into();
        state.downloaded = 0;
        state.total = assemble_bytes;
    });
    fs::create_dir_all(target).map_err(|error| error.to_string())?;
    let content_zip = target.join("content.zip");
    acz::assemble_overlay_zip(&entries, &blobs, &content_zip, |done| {
        let total = assemble_bytes;
        set_state(|state| state.downloaded = done.min(total));
    })?;

    let blob_list: String = acz::unique_entries(&entries)
        .into_iter()
        .map(|entry| entry.hash_hex)
        .collect::<Vec<_>>()
        .join("\n");
    fs::write(target.join("blobs.txt"), blob_list).map_err(|error| error.to_string())?;

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

fn blob_healthy(blobs: &Path, hash_hex: &str) -> bool {
    fs::read(blobs.join(format!("{hash_hex}.bin")))
        .map(|data| !data.is_empty() && acz::blake2b_hex(&data) == hash_hex)
        .unwrap_or(false)
}

fn blob_bytes(blobs: &Path, entries: &[acz::ManifestEntry]) -> u64 {
    entries
        .iter()
        .map(|entry| {
            fs::metadata(blobs.join(format!("{}.bin", entry.hash_hex)))
                .map(|meta| meta.len())
                .unwrap_or(0)
        })
        .sum()
}

fn is_sha256_hex(value: &str) -> bool {
    value.len() == 64 && value.chars().all(|c| c.is_ascii_hexdigit())
}

fn hash_prefix(hash: &str, length: usize) -> String {
    hash.chars().take(length).collect()
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
        if download_cancelled() {
            return Err("загрузка отменена".into());
        }
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
                if download_cancelled() {
                    return Err(last_error);
                }
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
            fs::remove_file(sidecar_path(&zip_path)).ok();
            return Err("хэш сборки не совпал, файл повреждён".into());
        }
    }

    set_state(|state| {
        state.phase = "extract".into();
        state.message = "распаковываем".into();
    });

    if target.exists() {
        let staging = target.parent().unwrap_or(root).join(format!(
            "{}.new-{}",
            target
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or("client"),
            std::process::id()
        ));
        if staging.exists() {
            fs::remove_dir_all(&staging).map_err(|error| error.to_string())?;
        }
        if let Err(message) = extract_zip(&zip_path, &staging) {
            let _ = fs::remove_dir_all(&staging);
            fs::remove_file(&zip_path).ok();
            fs::remove_file(sidecar_path(&zip_path)).ok();
            return Err(message);
        }
        let backup = target.parent().unwrap_or(root).join(format!(
            "{}.old-{}",
            target
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or("client"),
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&backup);
        fs::rename(target, &backup).map_err(|error| error.to_string())?;
        if fs::rename(&staging, target).is_err() {
            let _ = fs::rename(&backup, target);
            let _ = fs::remove_dir_all(&staging);
            fs::remove_file(&zip_path).ok();
            fs::remove_file(sidecar_path(&zip_path)).ok();
            return Err("не удалось заменить каталог клиента".into());
        }
        let _ = fs::remove_dir_all(&backup);
    } else {
        extract_zip(&zip_path, target)?;
    }
    fs::remove_file(&zip_path).ok();
    fs::remove_file(sidecar_path(&zip_path)).ok();

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
    match cleaned.as_str() {
        "" | "." | ".." => "client".into(),
        _ => cleaned,
    }
}

fn download_client() -> Result<reqwest::blocking::Client, String> {
    crate::http::with_route(
        reqwest::blocking::Client::builder(),
        crate::http::Route::Launcher,
    )
    .connect_timeout(DOWNLOAD_TIMEOUT)
    .timeout(DOWNLOAD_MAX_TIME)
    .build()
    .map_err(|error| error.to_string())
}

fn sidecar_path(path: &Path) -> PathBuf {
    let mut name = path.as_os_str().to_os_string();
    name.push(".url");
    PathBuf::from(name)
}

const DOWNLOAD_CHUNK: usize = 65_536;
const DOWNLOAD_STALL_TIMEOUT: Duration = Duration::from_secs(60);

fn download_to(url: &str, path: &Path) -> Result<(), String> {
    let client = download_client()?;
    let sidecar = sidecar_path(path);
    let resumed = fs::read_to_string(&sidecar)
        .map(|value| value.trim() == url)
        .unwrap_or(false)
        && fs::metadata(path)
            .map(|meta| meta.len() > 0)
            .unwrap_or(false);
    let mut offset = if resumed {
        fs::metadata(path).map(|meta| meta.len()).unwrap_or(0)
    } else {
        0
    };
    let mut request = client.get(url);
    if offset > 0 {
        request = request.header("Range", format!("bytes={offset}-"));
    }
    let response = request.send().map_err(|error| error.to_string())?;
    if offset > 0 && response.status().as_u16() == 206 {
        set_state(|state| state.message = "продолжаем загрузку".into());
    } else {
        offset = 0;
    }
    if response.status().as_u16() == 404 {
        return Err(format!("файл не найден: {url}"));
    }
    let mut response = response
        .error_for_status()
        .map_err(|error| error.to_string())?;
    let total = response
        .content_length()
        .map(|length| length + offset)
        .unwrap_or(0);
    set_state(|state| {
        state.total = total;
        state.downloaded = offset;
    });

    let mut file = if offset > 0 {
        fs::OpenOptions::new()
            .append(true)
            .open(path)
            .map_err(|error| error.to_string())?
    } else {
        fs::File::create(path).map_err(|error| error.to_string())?
    };
    fs::write(&sidecar, url).map_err(|error| error.to_string())?;

    let (sender, receiver) = mpsc::channel::<Result<Vec<u8>, String>>();
    thread::spawn(move || {
        let mut buffer = vec![0u8; DOWNLOAD_CHUNK];
        loop {
            match response.read(&mut buffer) {
                Ok(0) => {
                    let _ = sender.send(Ok(Vec::new()));
                    break;
                }
                Ok(size) => {
                    if sender.send(Ok(buffer[..size].to_vec())).is_err() {
                        break;
                    }
                }
                Err(error) => {
                    let _ = sender.send(Err(error.to_string()));
                    break;
                }
            }
        }
    });

    let mut downloaded: u64 = offset;
    let mut last_report: u64 = downloaded;
    loop {
        if download_cancelled() {
            return Err("загрузка отменена".into());
        }
        let chunk = match receiver.recv_timeout(DOWNLOAD_STALL_TIMEOUT) {
            Ok(Ok(chunk)) => chunk,
            Ok(Err(message)) => return Err(format!("обрыв загрузки: {message}")),
            Err(_) => {
                return Err(format!(
                    "загрузка приостановлена: нет данных {} секунд",
                    DOWNLOAD_STALL_TIMEOUT.as_secs()
                ))
            }
        };
        if chunk.is_empty() {
            break;
        }
        file.write_all(&chunk).map_err(|error| error.to_string())?;
        downloaded += chunk.len() as u64;
        if downloaded - last_report >= 262_144 || chunk.len() < DOWNLOAD_CHUNK {
            last_report = downloaded;
            let current = downloaded;
            set_state(|state| {
                state.total = if total > 0 { total } else { current };
                state.downloaded = current.min(state.total);
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
        assert_eq!(sanitize_component(""), "client");
        assert_eq!(sanitize_component("."), "client");
        assert_eq!(sanitize_component(".."), "client");
        assert_eq!(sanitize_component("a/b"), "a_b");
        assert_eq!(sanitize_component("CON"), "CON");
        assert_eq!(sanitize_component("сервер"), "______");
    }

    #[test]
    fn shortens_hash_without_byte_slices() {
        let digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
        assert_eq!(hash_prefix(digest, 8), "ba7816bf");
        assert_eq!(hash_prefix("кириллица", 8), "кириллиц");
        assert_eq!(hash_prefix("", 8), "");
        assert!(is_sha256_hex(digest));
        assert!(!is_sha256_hex("abc"));
        assert!(!is_sha256_hex("не хэш"));
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
            engine_zip: "/cache/engine.zip".into(),
            engine_sig: "sig".into(),
            manifest_url: "https://example.test/manifest.yml".into(),
            manifest_download_url: "https://example.test/download".into(),
        };
        write_marker(&dir, &build).unwrap();
        let read = read_marker(&dir).unwrap();
        assert_eq!(read.version, "240.1");
        assert_eq!(read.hash, "abcd");
        assert_eq!(read.manifest_hash, "feed");
        assert_eq!(read.engine_version, "240.1.0.5");
        assert_eq!(read.engine_zip, "/cache/engine.zip");
        assert_eq!(read.engine_sig, "sig");
        assert_eq!(read.manifest_url, "https://example.test/manifest.yml");
        assert_eq!(read.manifest_download_url, "https://example.test/download");
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

    #[test]
    fn reads_bundle_meta() {
        let dir = std::env::temp_dir().join(format!("illusio-bundle-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let zip_path = dir.join("replay.zip");
        let file = fs::File::create(&zip_path).unwrap();
        let mut writer = zip::ZipWriter::new(file);
        let options = zip::write::SimpleFileOptions::default();
        writer
            .start_file("rt_content_bundle.json", options)
            .unwrap();
        writer.write_all(
            br#"{"server_gc":true,"engine_version":"240.1.0.5","base_build":{"download_url":"https://cdn.example.com/builds","version":"240.1","fork_id":"space_wizards","hash":"abc"}}"#,
        ).unwrap();
        writer
            .start_file("data/save.bin", zip::write::SimpleFileOptions::default())
            .unwrap();
        writer.write_all(b"round").unwrap();
        writer.finish().unwrap();
        let (meta, has_manifest) = read_bundle_meta(&zip_path).unwrap();
        assert!(!has_manifest);
        assert_eq!(meta.engine_version, "240.1.0.5");
        assert_eq!(meta.base_build.fork_id, "space_wizards");
        assert_eq!(meta.base_build.hash, "abc");
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn detects_full_bundle_by_manifest() {
        let dir = std::env::temp_dir().join(format!("illusio-bundle-full-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let zip_path = dir.join("full.zip");
        let file = fs::File::create(&zip_path).unwrap();
        let mut writer = zip::ZipWriter::new(file);
        let options = zip::write::SimpleFileOptions::default();
        writer.start_file("manifest.yml", options).unwrap();
        writer.write_all(b"files: []").unwrap();
        writer
            .start_file("rt_content_bundle.json", options)
            .unwrap();
        writer
            .write_all(br#"{"engine_version":"240.1.0.5"}"#)
            .unwrap();
        writer.finish().unwrap();
        let (meta, has_manifest) = read_bundle_meta(&zip_path).unwrap();
        assert!(has_manifest);
        assert_eq!(meta.engine_version, "240.1.0.5");
        assert!(meta.base_build.download_url.is_empty());
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn rejects_zip_without_bundle_marker() {
        let dir = std::env::temp_dir().join(format!("illusio-bundle-bad-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let zip_path = dir.join("plain.zip");
        let file = fs::File::create(&zip_path).unwrap();
        let mut writer = zip::ZipWriter::new(file);
        writer
            .start_file("readme.txt", zip::write::SimpleFileOptions::default())
            .unwrap();
        writer.write_all(b"hi").unwrap();
        writer.finish().unwrap();
        assert!(read_bundle_meta(&zip_path).is_err());
        fs::remove_dir_all(&dir).ok();
    }
}

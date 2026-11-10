#![allow(clippy::missing_safety_doc)]

pub mod acz;
pub mod auth;
pub mod config;
pub mod cull;
pub mod engine;
pub mod engines;
pub mod health;
pub mod http;
pub mod hub;
pub mod install;
pub mod ipc;
mod launch;
pub mod modules;
pub mod packs;
pub mod socks;
pub mod status;
pub mod sys;
pub mod update;

use serde::Deserialize;
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::ptr;

fn to_ptr(value: String) -> *mut c_char {
    match CString::new(value) {
        Ok(c_string) => c_string.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

fn read_ptr(pointer: *const c_char) -> String {
    if pointer.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(pointer).to_string_lossy().into_owned() }
}

fn guarded<F>(job: F) -> *mut c_char
where
    F: FnOnce() -> String,
{
    let result = catch_unwind(AssertUnwindSafe(job)).unwrap_or_else(|_| {
        serde_json::json!({"ok": false, "error": "внутренняя ошибка ядра"}).to_string()
    });
    to_ptr(result)
}

#[no_mangle]
pub extern "C" fn illusio_version() -> *mut c_char {
    guarded(|| serde_json::json!({"ok": true, "version": env!("CARGO_PKG_VERSION")}).to_string())
}

#[no_mangle]
pub extern "C" fn illusio_config_dir() -> *mut c_char {
    guarded(|| match config::config_dir() {
        Some(path) => serde_json::json!({
            "ok": true,
            "path": path.display().to_string(),
        })
        .to_string(),
        None => serde_json::json!({
            "ok": false,
            "error": "каталог конфигурации не найден",
        })
        .to_string(),
    })
}

#[no_mangle]
pub extern "C" fn illusio_load_config() -> *mut c_char {
    guarded(|| match config::load() {
        Ok(value) => serde_json::json!({
            "ok": true,
            "config": value,
        })
        .to_string(),
        Err(message) => serde_json::json!({
            "ok": false,
            "error": message,
        })
        .to_string(),
    })
}

#[no_mangle]
pub unsafe extern "C" fn illusio_save_config(raw: *const c_char) -> *mut c_char {
    guarded(
        || match serde_json::from_str::<config::Config>(&read_ptr(raw)) {
            Ok(value) => match config::save(&value) {
                Ok(()) => serde_json::json!({"ok": true}).to_string(),
                Err(message) => serde_json::json!({
                    "ok": false,
                    "error": message,
                })
                .to_string(),
            },
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message.to_string(),
            })
            .to_string(),
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn illusio_fetch_status(url: *const c_char) -> *mut c_char {
    guarded(|| match status::fetch_status(&read_ptr(url)) {
        Ok(value) => serde_json::json!({
            "ok": true,
            "status": value,
        })
        .to_string(),
        Err(message) => serde_json::json!({
            "ok": false,
            "error": message,
        })
        .to_string(),
    })
}

#[no_mangle]
pub unsafe extern "C" fn illusio_launch(raw: *const c_char) -> *mut c_char {
    guarded(
        || match serde_json::from_str::<launch::LaunchSpec>(&read_ptr(raw)) {
            Ok(spec) => match launch::launch(&spec) {
                Ok(pid) => serde_json::json!({
                    "ok": true,
                    "pid": pid,
                })
                .to_string(),
                Err(message) => serde_json::json!({
                    "ok": false,
                    "error": message,
                })
                .to_string(),
            },
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message.to_string(),
            })
            .to_string(),
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn illusio_fetch_info(url: *const c_char) -> *mut c_char {
    guarded(|| match install::fetch_info(&read_ptr(url)) {
        Ok(value) => serde_json::json!({
            "ok": true,
            "info": value,
        })
        .to_string(),
        Err(message) => serde_json::json!({
            "ok": false,
            "error": message,
        })
        .to_string(),
    })
}

#[no_mangle]
pub extern "C" fn illusio_default_install_dir() -> *mut c_char {
    guarded(|| match install::default_install_dir() {
        Some(path) => serde_json::json!({
            "ok": true,
            "path": path.display().to_string(),
        })
        .to_string(),
        None => serde_json::json!({
            "ok": false,
            "error": "каталог установки не найден",
        })
        .to_string(),
    })
}

#[no_mangle]
pub unsafe extern "C" fn illusio_start_download(raw: *const c_char) -> *mut c_char {
    guarded(
        || match serde_json::from_str::<install::DownloadSpec>(&read_ptr(raw)) {
            Ok(spec) => match install::start_download(spec) {
                Ok(()) => serde_json::json!({"ok": true}).to_string(),
                Err(message) => serde_json::json!({
                    "ok": false,
                    "error": message,
                })
                .to_string(),
            },
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message.to_string(),
            })
            .to_string(),
        },
    )
}

#[no_mangle]
pub extern "C" fn illusio_download_state() -> *mut c_char {
    guarded(|| {
        serde_json::json!({
            "ok": true,
            "state": install::snapshot(),
        })
        .to_string()
    })
}

#[derive(Deserialize)]
struct AuthPayload {
    #[serde(default)]
    auth_url: String,
    #[serde(default)]
    username: String,
    #[serde(default)]
    password: String,
    #[serde(default)]
    tfa_code: String,
}

#[derive(Deserialize)]
struct RefreshPayload {
    #[serde(default)]
    auth_url: String,
    #[serde(default)]
    username: String,
    #[serde(default)]
    user_id: String,
    #[serde(default)]
    token: String,
    #[serde(default)]
    hwid: String,
}

#[derive(Deserialize)]
struct TokenPayload {
    #[serde(default)]
    auth_url: String,
    #[serde(default)]
    token: String,
}

#[no_mangle]
pub unsafe extern "C" fn illusio_authenticate(raw: *const c_char) -> *mut c_char {
    guarded(
        || match serde_json::from_str::<AuthPayload>(&read_ptr(raw)) {
            Ok(payload) => {
                match auth::authenticate(
                    &payload.auth_url,
                    &payload.username,
                    &payload.password,
                    Some(&payload.tfa_code),
                ) {
                    Ok(login) => serde_json::json!({"ok": true, "login": login}).to_string(),
                    Err(error) => serde_json::json!({
                        "ok": false,
                        "error": error.message,
                        "code": error.code,
                    })
                    .to_string(),
                }
            }
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message.to_string(),
            })
            .to_string(),
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn illusio_refresh_login(raw: *const c_char) -> *mut c_char {
    guarded(
        || match serde_json::from_str::<RefreshPayload>(&read_ptr(raw)) {
            Ok(payload) => {
                let login = auth::LoginInfo {
                    token: payload.token,
                    username: payload.username,
                    user_id: payload.user_id,
                    expire_time: String::new(),
                    auth_server: auth::normalize_auth_url(&payload.auth_url),
                    hwid: payload.hwid,
                };
                match auth::refresh(&payload.auth_url, &login) {
                    Ok(updated) => serde_json::json!({"ok": true, "login": updated}).to_string(),
                    Err(message) => serde_json::json!({
                        "ok": false,
                        "error": message,
                    })
                    .to_string(),
                }
            }
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message.to_string(),
            })
            .to_string(),
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn illusio_check_token(raw: *const c_char) -> *mut c_char {
    guarded(
        || match serde_json::from_str::<TokenPayload>(&read_ptr(raw)) {
            Ok(payload) => match auth::check_token(&payload.auth_url, &payload.token) {
                Ok(valid) => serde_json::json!({"ok": true, "valid": valid}).to_string(),
                Err(message) => serde_json::json!({
                    "ok": false,
                    "error": message,
                })
                .to_string(),
            },
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message.to_string(),
            })
            .to_string(),
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn illusio_logout(raw: *const c_char) -> *mut c_char {
    guarded(
        || match serde_json::from_str::<TokenPayload>(&read_ptr(raw)) {
            Ok(payload) => match auth::logout(&payload.auth_url, &payload.token) {
                Ok(()) => serde_json::json!({"ok": true}).to_string(),
                Err(message) => serde_json::json!({
                    "ok": false,
                    "error": message,
                })
                .to_string(),
            },
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message.to_string(),
            })
            .to_string(),
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn illusio_fetch_servers(raw: *const c_char) -> *mut c_char {
    guarded(|| {
        let payload = read_ptr(raw);
        let trimmed = payload.trim();
        let result = if trimmed.starts_with('[') {
            let hubs: Vec<String> = serde_json::from_str(trimmed).unwrap_or_default();
            hub::fetch_servers_multi(&hubs)
        } else {
            hub::fetch_servers_multi(&[trimmed.to_string()])
        };
        match result {
            Ok(servers) => serde_json::json!({
                "ok": true,
                "servers": servers,
            })
            .to_string(),
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message,
            })
            .to_string(),
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn illusio_ping_servers(raw: *const c_char) -> *mut c_char {
    guarded(|| {
        let payload = read_ptr(raw);
        let urls: Vec<String> = serde_json::from_str(payload.trim()).unwrap_or_default();
        let pings = hub::ping_servers(&urls);
        serde_json::json!({
            "ok": true,
            "pings": pings,
        })
        .to_string()
    })
}

#[no_mangle]
pub extern "C" fn illusio_logs_dir() -> *mut c_char {
    guarded(|| match config::logs_dir() {
        Some(path) => serde_json::json!({
            "ok": true,
            "path": path.display().to_string(),
        })
        .to_string(),
        None => serde_json::json!({
            "ok": false,
            "error": "каталог конфигурации не найден",
        })
        .to_string(),
    })
}

#[no_mangle]
pub unsafe extern "C" fn illusio_open_url(url: *const c_char) -> *mut c_char {
    guarded(|| match sys::open_with_system(&read_ptr(url)) {
        Ok(()) => serde_json::json!({"ok": true}).to_string(),
        Err(message) => serde_json::json!({
            "ok": false,
            "error": message,
        })
        .to_string(),
    })
}

#[no_mangle]
pub unsafe extern "C" fn illusio_open_path(path: *const c_char) -> *mut c_char {
    guarded(|| match sys::open_with_system(&read_ptr(path)) {
        Ok(()) => serde_json::json!({"ok": true}).to_string(),
        Err(message) => serde_json::json!({
            "ok": false,
            "error": message,
        })
        .to_string(),
    })
}

#[no_mangle]
pub unsafe extern "C" fn illusio_scan_mods(raw: *const c_char) -> *mut c_char {
    guarded(|| {
        let payload = read_ptr(raw);
        let trimmed = payload.trim();
        let (dir_raw, loader_dir) = if trimmed.starts_with('{') {
            match serde_json::from_str::<serde_json::Value>(trimmed) {
                Ok(value) => (
                    value["path"].as_str().unwrap_or_default().to_string(),
                    value["loader_dir"].as_str().unwrap_or_default().to_string(),
                ),
                Err(_) => (payload.clone(), String::new()),
            }
        } else {
            (payload, String::new())
        };
        let dir = PathBuf::from(&dir_raw);
        let metadata = if loader_dir.trim().is_empty() {
            Vec::new()
        } else {
            sys::read_dll_metadata(&PathBuf::from(loader_dir.trim()), &dir)
        };
        match sys::ensure_dir(&dir).and_then(|_| sys::scan_mods(&dir, &metadata)) {
            Ok(mods) => serde_json::json!({
                "ok": true,
                "mods": mods,
                "path": dir.display().to_string(),
            })
            .to_string(),
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message,
            })
            .to_string(),
        }
    })
}

#[no_mangle]
pub extern "C" fn illusio_mods_dir() -> *mut c_char {
    guarded(|| match config::mods_dir() {
        Some(path) => serde_json::json!({
            "ok": true,
            "path": path.display().to_string(),
        })
        .to_string(),
        None => serde_json::json!({
            "ok": false,
            "error": "каталог конфигурации не найден",
        })
        .to_string(),
    })
}

#[no_mangle]
pub extern "C" fn illusio_res_packs_dir() -> *mut c_char {
    guarded(|| match config::res_packs_dir() {
        Some(path) => serde_json::json!({
            "ok": true,
            "path": path.display().to_string(),
        })
        .to_string(),
        None => serde_json::json!({
            "ok": false,
            "error": "каталог конфигурации не найден",
        })
        .to_string(),
    })
}

#[no_mangle]
pub extern "C" fn illusio_dumps_dir() -> *mut c_char {
    guarded(|| match config::dumps_dir() {
        Some(path) => serde_json::json!({
            "ok": true,
            "path": path.display().to_string(),
        })
        .to_string(),
        None => serde_json::json!({
            "ok": false,
            "error": "каталог конфигурации не найден",
        })
        .to_string(),
    })
}

#[no_mangle]
pub unsafe extern "C" fn illusio_list_packs(raw: *const c_char) -> *mut c_char {
    guarded(|| {
        let dir = PathBuf::from(read_ptr(raw).trim());
        match sys::ensure_dir(&dir) {
            Ok(_) => serde_json::json!({
                "ok": true,
                "packs": packs::list_packs(&dir),
                "path": dir.display().to_string(),
            })
            .to_string(),
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message,
            })
            .to_string(),
        }
    })
}

#[derive(Deserialize)]
struct ProxyProbePayload {
    #[serde(default)]
    host: String,
    #[serde(default)]
    port: i64,
    #[serde(default)]
    username: String,
    #[serde(default)]
    password: String,
    #[serde(default)]
    udp: bool,
}

#[derive(Deserialize)]
struct ProxySessionPayload {
    #[serde(default)]
    enabled: bool,
}

#[derive(Deserialize)]
struct VersionPayload {
    #[serde(default)]
    current: String,
    #[serde(default)]
    prerelease: bool,
}

#[derive(Deserialize)]
struct InstallPayload {
    #[serde(default)]
    url: String,
    #[serde(default)]
    name: String,
}

#[no_mangle]
pub unsafe extern "C" fn illusio_proxy_session(raw: *const c_char) -> *mut c_char {
    guarded(
        || match serde_json::from_str::<ProxySessionPayload>(&read_ptr(raw)) {
            Ok(payload) => {
                http::set_session_proxy(payload.enabled);
                serde_json::json!({"ok": true}).to_string()
            }
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message.to_string(),
            })
            .to_string(),
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn illusio_proxy_probe(raw: *const c_char) -> *mut c_char {
    guarded(
        || match serde_json::from_str::<ProxyProbePayload>(&read_ptr(raw)) {
            Ok(payload) => {
                let proxy = config::ProxyConfig {
                    launcher: true,
                    updates: false,
                    region: false,
                    host: payload.host.trim().to_string(),
                    port: payload.port.clamp(0, 65535) as u16,
                    username: payload.username,
                    password: payload.password,
                    udp_relay: false,
                    apply_to_game: false,
                };
                if proxy.host.is_empty() || proxy.port == 0 {
                    return serde_json::json!({
                        "ok": false,
                        "error": "укажите адрес и порт прокси",
                    })
                    .to_string();
                }
                match socks::probe_tcp(&proxy) {
                    Ok(rtt) => {
                        let (udp_ok, udp_error) = if payload.udp {
                            match socks::probe_udp(&proxy) {
                                Ok(()) => (true, String::new()),
                                Err(error) => (false, error),
                            }
                        } else {
                            (false, String::new())
                        };
                        serde_json::json!({
                            "ok": true,
                            "rtt_ms": rtt,
                            "udp_ok": udp_ok,
                            "udp_error": udp_error,
                        })
                        .to_string()
                    }
                    Err(error) => serde_json::json!({
                        "ok": false,
                        "error": error,
                    })
                    .to_string(),
                }
            }
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message.to_string(),
            })
            .to_string(),
        },
    )
}

#[no_mangle]
pub extern "C" fn illusio_clear_cache() -> *mut c_char {
    guarded(|| match sys::clear_cache() {
        Ok(()) => serde_json::json!({"ok": true}).to_string(),
        Err(message) => serde_json::json!({
            "ok": false,
            "error": message,
        })
        .to_string(),
    })
}

#[no_mangle]
pub extern "C" fn illusio_cull_content() -> *mut c_char {
    guarded(
        || match config::load().and_then(|value| cull::cull(&value)) {
            Ok(report) => serde_json::json!({
                "ok": true,
                "files": report.files,
                "bytes": report.bytes,
            })
            .to_string(),
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message,
            })
            .to_string(),
        },
    )
}

#[derive(Deserialize)]
struct ContentStatePayload {
    #[serde(default, rename = "server_url")]
    server_url: String,
    #[serde(default, rename = "install_dir")]
    install_dir: String,
}

#[no_mangle]
pub unsafe extern "C" fn illusio_content_state(raw: *const c_char) -> *mut c_char {
    guarded(
        || match serde_json::from_str::<ContentStatePayload>(&read_ptr(raw)) {
            Ok(payload) => {
                match install::content_state(&payload.server_url, &payload.install_dir) {
                    Ok(actual) => serde_json::json!({
                        "ok": true,
                        "actual": actual,
                    })
                    .to_string(),
                    Err(message) => serde_json::json!({
                        "ok": false,
                        "error": message,
                    })
                    .to_string(),
                }
            }
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message.to_string(),
            })
            .to_string(),
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn illusio_update_check(raw: *const c_char) -> *mut c_char {
    guarded(
        || match serde_json::from_str::<VersionPayload>(&read_ptr(raw)) {
            Ok(payload) => match update::check_ex(&payload.current, payload.prerelease) {
                Ok(value) => serde_json::json!({
                    "ok": true,
                    "available": value.available,
                    "version": value.version,
                    "notes": value.notes,
                    "assetName": value.asset_name,
                    "assetUrl": value.asset_url,
                })
                .to_string(),
                Err(message) => serde_json::json!({
                    "ok": false,
                    "error": message,
                })
                .to_string(),
            },
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message.to_string(),
            })
            .to_string(),
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn illusio_self_update(raw: *const c_char) -> *mut c_char {
    guarded(
        || match serde_json::from_str::<VersionPayload>(&read_ptr(raw)) {
            Ok(payload) => {
                let release = match update::check_ex(&payload.current, payload.prerelease) {
                    Ok(value) if value.available => value,
                    Ok(_) => {
                        return serde_json::json!({"ok": true, "updated": false}).to_string();
                    }
                    Err(message) => {
                        return serde_json::json!({"ok": false, "error": message}).to_string();
                    }
                };
                let result = update::download_asset(
                    &release.asset_url,
                    &std::env::temp_dir().join("illusio-update"),
                    &release.asset_name,
                )
                .and_then(|archive| update::apply(&archive).map(|()| release.version.clone()));
                match result {
                    Ok(version) => serde_json::json!({
                        "ok": true,
                        "updated": true,
                        "version": version,
                    })
                    .to_string(),
                    Err(message) => serde_json::json!({
                        "ok": false,
                        "error": message,
                    })
                    .to_string(),
                }
            }
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message.to_string(),
            })
            .to_string(),
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn illusio_releases_list(raw: *const c_char) -> *mut c_char {
    guarded(
        || match serde_json::from_str::<VersionPayload>(&read_ptr(raw)) {
            Ok(payload) => match update::list_releases(&payload.current) {
                Ok(releases) => serde_json::json!({"ok": true, "releases": releases}).to_string(),
                Err(message) => serde_json::json!({
                    "ok": false,
                    "error": message,
                })
                .to_string(),
            },
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message.to_string(),
            })
            .to_string(),
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn illusio_release_install(raw: *const c_char) -> *mut c_char {
    guarded(
        || match serde_json::from_str::<InstallPayload>(&read_ptr(raw)) {
            Ok(payload) => match update::install_release(&payload.url, &payload.name) {
                Ok(()) => serde_json::json!({"ok": true}).to_string(),
                Err(message) => serde_json::json!({
                    "ok": false,
                    "error": message,
                })
                .to_string(),
            },
            Err(message) => serde_json::json!({
                "ok": false,
                "error": message.to_string(),
            })
            .to_string(),
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn illusio_update_finalize() -> *mut c_char {
    guarded(|| match update::finalize_pending() {
        Ok(applied) => serde_json::json!({"ok": true, "applied": applied}).to_string(),
        Err(message) => serde_json::json!({"ok": false, "error": message}).to_string(),
    })
}

#[no_mangle]
pub unsafe extern "C" fn illusio_ipc_init(raw: *const c_char) -> *mut c_char {
    guarded(|| {
        let args: Vec<String> = serde_json::from_str(&read_ptr(raw)).unwrap_or_default();
        match ipc::init(&args) {
            Ok(primary) => serde_json::json!({"ok": true, "primary": primary}).to_string(),
            Err(message) => serde_json::json!({"ok": false, "error": message}).to_string(),
        }
    })
}

#[no_mangle]
pub extern "C" fn illusio_ipc_poll() -> *mut c_char {
    guarded(|| {
        serde_json::json!({
            "ok": true,
            "url": ipc::poll().unwrap_or_default(),
        })
        .to_string()
    })
}

#[no_mangle]
pub extern "C" fn illusio_launch_status() -> *mut c_char {
    guarded(|| {
        serde_json::json!({
            "ok": true,
            "status": launch::status_snapshot(),
        })
        .to_string()
    })
}

#[no_mangle]
pub extern "C" fn illusio_health() -> *mut c_char {
    guarded(|| {
        serde_json::json!({
            "ok": true,
            "health": health::report(),
        })
        .to_string()
    })
}

#[no_mangle]
pub unsafe extern "C" fn illusio_engine_modules(raw: *const c_char) -> *mut c_char {
    #[derive(Deserialize)]
    struct Payload {
        #[serde(default)]
        path: String,
    }

    guarded(|| match serde_json::from_str::<Payload>(&read_ptr(raw)) {
        Ok(payload) => match modules::read_names(std::path::Path::new(payload.path.trim())) {
            Ok(names) => serde_json::json!({"ok": true, "modules": names}).to_string(),
            Err(message) => serde_json::json!({"ok": false, "error": message}).to_string(),
        },
        Err(message) => serde_json::json!({"ok": false, "error": message.to_string()}).to_string(),
    })
}

#[no_mangle]
pub unsafe extern "C" fn illusio_engines_import(raw: *const c_char) -> *mut c_char {
    #[derive(Deserialize)]
    struct Payload {
        #[serde(default)]
        path: String,
    }

    guarded(|| match serde_json::from_str::<Payload>(&read_ptr(raw)) {
        Ok(payload) => match engines::import(std::path::Path::new(payload.path.trim())) {
            Ok(engine) => serde_json::json!({"ok": true, "engine": engine}).to_string(),
            Err(message) => serde_json::json!({"ok": false, "error": message}).to_string(),
        },
        Err(message) => serde_json::json!({"ok": false, "error": message.to_string()}).to_string(),
    })
}

#[no_mangle]
pub extern "C" fn illusio_engines_list() -> *mut c_char {
    guarded(|| {
        let engines = engines::list();
        let dir = engines::engines_dir()
            .map(|value| value.display().to_string())
            .unwrap_or_default();
        serde_json::json!({"ok": true, "engines": engines, "dir": dir}).to_string()
    })
}

#[no_mangle]
pub unsafe extern "C" fn illusio_engines_remove(raw: *const c_char) -> *mut c_char {
    #[derive(Deserialize)]
    struct Payload {
        #[serde(default)]
        id: String,
    }

    guarded(|| match serde_json::from_str::<Payload>(&read_ptr(raw)) {
        Ok(payload) => match engines::remove(payload.id.trim()) {
            Ok(()) => serde_json::json!({"ok": true}).to_string(),
            Err(message) => serde_json::json!({"ok": false, "error": message}).to_string(),
        },
        Err(message) => serde_json::json!({"ok": false, "error": message.to_string()}).to_string(),
    })
}

#[no_mangle]
pub unsafe extern "C" fn illusio_free(pointer: *mut c_char) {
    if pointer.is_null() {
        return;
    }
    drop(CString::from_raw(pointer));
}

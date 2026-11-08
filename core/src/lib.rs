#![allow(clippy::missing_safety_doc)]

pub mod acz;
pub mod auth;
pub mod config;
pub mod engine;
pub mod install;
mod launch;
pub mod status;

use serde::Deserialize;
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
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
pub unsafe extern "C" fn illusio_free(pointer: *mut c_char) {
    if pointer.is_null() {
        return;
    }
    drop(CString::from_raw(pointer));
}

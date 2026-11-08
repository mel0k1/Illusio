#![allow(clippy::missing_safety_doc)]

pub mod config;
mod launch;
pub mod status;

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
pub unsafe extern "C" fn illusio_free(pointer: *mut c_char) {
    if pointer.is_null() {
        return;
    }
    drop(CString::from_raw(pointer));
}

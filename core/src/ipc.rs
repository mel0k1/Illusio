use std::collections::VecDeque;
#[cfg(unix)]
use std::io::{Read, Write};
use std::sync::{Mutex, OnceLock};

static QUEUE: OnceLock<Mutex<VecDeque<String>>> = OnceLock::new();

fn queue() -> &'static Mutex<VecDeque<String>> {
    QUEUE.get_or_init(|| Mutex::new(VecDeque::new()))
}

pub const WINDOW_NAME: &str = r"\\.\pipe\illusio";

pub fn extract_links(args: &[String]) -> Vec<String> {
    let mut links: Vec<String> = Vec::new();
    for argument in args {
        let trimmed = argument.trim();
        let lowered = trimmed.to_ascii_lowercase();
        let is_link = lowered.starts_with("ss14://") || lowered.starts_with("ss14s://");
        if is_link && !links.iter().any(|existing| existing == trimmed) {
            links.push(trimmed.to_string());
        }
    }
    links
}

pub fn parse_payload(raw: &[u8]) -> Vec<String> {
    let text = String::from_utf8_lossy(raw);
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Vec::new();
    }
    if let Ok(links) = serde_json::from_str::<Vec<String>>(trimmed) {
        return extract_links(&links);
    }
    extract_links(&[trimmed.to_string()])
}

pub fn init(args: &[String]) -> Result<bool, String> {
    let links = extract_links(args);
    if forward(&links) {
        return Ok(false);
    }
    if let Ok(mut guard) = queue().lock() {
        for link in links {
            guard.push_back(link);
        }
    }
    spawn_server();
    Ok(true)
}

pub fn poll() -> Option<String> {
    let mut guard = queue().lock().ok()?;
    guard.pop_front()
}

fn forward(links: &[String]) -> bool {
    if let Ok(body) = serde_json::to_vec(links) {
        return send(&body);
    }
    false
}

fn spawn_server() {
    std::thread::spawn(|| {
        #[cfg(windows)]
        pipe_server();
        #[cfg(unix)]
        socket_server();
    });
}

#[cfg(unix)]
fn socket_path() -> Option<std::path::PathBuf> {
    crate::config::config_dir().map(|dir| dir.join("illusio.sock"))
}

#[cfg(unix)]
fn send(body: &[u8]) -> bool {
    use std::os::unix::net::UnixStream;
    let Some(path) = socket_path() else {
        return false;
    };
    let Ok(mut stream) = UnixStream::connect(&path) else {
        return false;
    };
    stream.write_all(body).is_ok()
}

#[cfg(unix)]
fn socket_server() {
    use std::os::unix::net::UnixListener;
    let Some(path) = socket_path() else {
        return;
    };
    let _ = std::fs::remove_file(&path);
    let Ok(listener) = UnixListener::bind(&path) else {
        return;
    };
    for stream in listener.incoming() {
        let Ok(mut stream) = stream else {
            continue;
        };
        let mut buffer = Vec::new();
        if stream.read_to_end(&mut buffer).is_ok() {
            for link in parse_payload(&buffer) {
                if let Ok(mut guard) = queue().lock() {
                    guard.push_back(link);
                }
            }
        }
    }
}

#[cfg(windows)]
fn send(body: &[u8]) -> bool {
    use windows_sys::Win32::Foundation::{CloseHandle, GENERIC_WRITE, INVALID_HANDLE_VALUE};
    use windows_sys::Win32::Storage::FileSystem::{CreateFileW, WriteFile, OPEN_EXISTING};

    let name: Vec<u16> = WINDOW_NAME.encode_utf16().chain([0]).collect();
    let handle = unsafe {
        CreateFileW(
            name.as_ptr(),
            GENERIC_WRITE,
            0,
            std::ptr::null(),
            OPEN_EXISTING,
            0,
            std::ptr::null_mut(),
        )
    };
    if handle == INVALID_HANDLE_VALUE || handle.is_null() {
        return false;
    }
    let mut written: u32 = 0;
    let ok = unsafe {
        WriteFile(
            handle,
            body.as_ptr(),
            body.len() as u32,
            &mut written,
            std::ptr::null_mut(),
        )
    };
    unsafe {
        CloseHandle(handle);
    }
    ok != 0
}

#[cfg(windows)]
fn pipe_server() {
    use windows_sys::Win32::Foundation::{CloseHandle, GetLastError, ERROR_PIPE_CONNECTED};
    use windows_sys::Win32::Storage::FileSystem::{ReadFile, PIPE_ACCESS_INBOUND};
    use windows_sys::Win32::System::Pipes::{
        ConnectNamedPipe, CreateNamedPipeW, DisconnectNamedPipe, PIPE_READMODE_BYTE,
        PIPE_TYPE_BYTE, PIPE_WAIT,
    };

    let name: Vec<u16> = WINDOW_NAME.encode_utf16().chain([0]).collect();
    loop {
        let pipe = unsafe {
            CreateNamedPipeW(
                name.as_ptr(),
                PIPE_ACCESS_INBOUND,
                PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
                1,
                4096,
                4096,
                0,
                std::ptr::null(),
            )
        };
        if pipe.is_null() {
            return;
        }
        let connected = unsafe { ConnectNamedPipe(pipe, std::ptr::null_mut()) };
        if connected == 0 {
            let error = unsafe { GetLastError() };
            if error != ERROR_PIPE_CONNECTED {
                unsafe {
                    CloseHandle(pipe);
                }
                continue;
            }
        }
        let mut buffer = vec![0u8; 4096];
        let mut received: Vec<u8> = Vec::new();
        loop {
            let mut read: u32 = 0;
            let ok = unsafe {
                ReadFile(
                    pipe,
                    buffer.as_mut_ptr(),
                    buffer.len() as u32,
                    &mut read,
                    std::ptr::null_mut(),
                )
            };
            if ok == 0 || read == 0 {
                break;
            }
            received.extend_from_slice(&buffer[..read as usize]);
            if received.len() > 64 * 1024 {
                break;
            }
        }
        unsafe {
            DisconnectNamedPipe(pipe);
            CloseHandle(pipe);
        }
        for link in parse_payload(&received) {
            if let Ok(mut guard) = queue().lock() {
                guard.push_back(link);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_links_from_args() {
        let args = vec![
            "--some-flag".to_string(),
            "ss14://wormix14.site".to_string(),
            "  SS14s://Cinka.ru/meow/3d ".to_string(),
            "https://example.com".to_string(),
            "ss14://wormix14.site".to_string(),
        ];
        assert_eq!(
            extract_links(&args),
            vec![
                "ss14://wormix14.site".to_string(),
                "SS14s://Cinka.ru/meow/3d".to_string(),
            ]
        );
        assert!(extract_links(&[]).is_empty());
    }

    #[test]
    fn parses_forwarded_payloads() {
        let body = serde_json::to_vec(&vec!["ss14://a.example", "ss14s://b.example"]).unwrap();
        assert_eq!(
            parse_payload(&body),
            vec![
                "ss14://a.example".to_string(),
                "ss14s://b.example".to_string()
            ]
        );
        assert_eq!(
            parse_payload(b" ss14://plain.example "),
            vec!["ss14://plain.example".to_string()]
        );
        assert!(parse_payload(b"").is_empty());
        assert!(parse_payload(b"garbage").is_empty());
    }

    #[test]
    fn poll_without_links_returns_none() {
        while poll().is_some() {}
        assert_eq!(poll(), None);
    }
}

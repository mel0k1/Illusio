use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, Default, Serialize)]
pub struct ModEntry {
    pub file_name: String,
    pub path: String,
    pub size: u64,
    pub kind: String,
    pub name: String,
    pub description: String,
    pub version: String,
    pub game: bool,
    pub preload: bool,
}

#[derive(Debug, Clone, Default, serde::Deserialize)]
pub struct DllMeta {
    #[serde(default, rename = "file")]
    pub file_name: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub version: String,
    #[serde(default)]
    pub game: bool,
    #[serde(default)]
    pub preload: bool,
}

pub fn ensure_dir(path: &Path) -> Result<PathBuf, String> {
    fs::create_dir_all(path).map_err(|error| format!("не удалось создать каталог: {error}"))?;
    Ok(path.to_path_buf())
}

fn is_http_url(target: &str) -> bool {
    let trimmed = target.trim();
    let Some((scheme, rest)) = trimmed.split_once("://") else {
        return false;
    };
    if rest.is_empty() {
        return false;
    }
    scheme.eq_ignore_ascii_case("http") || scheme.eq_ignore_ascii_case("https")
}

pub fn open_with_system(target: &str) -> Result<(), String> {
    if !is_http_url(target) {
        return Err("поддерживаются только ссылки http и https".into());
    }
    open_any(target)
}

pub fn open_path(path: &str) -> Result<(), String> {
    if path.trim().is_empty() {
        return Err("путь не указан".into());
    }
    open_any(path)
}

fn open_any(target: &str) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        shell_open(target)
    }
    #[cfg(target_os = "macos")]
    {
        spawn_open("open", target)
    }
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        spawn_open("xdg-open", target)
    }
}

#[cfg(not(target_os = "windows"))]
fn spawn_open(program: &str, target: &str) -> Result<(), String> {
    Command::new(program)
        .arg(target)
        .spawn()
        .map(|_| ())
        .map_err(|error| format!("не удалось открыть: {error}"))
}

#[cfg(target_os = "windows")]
fn shell_open(target: &str) -> Result<(), String> {
    use windows_sys::Win32::UI::Shell::ShellExecuteW;
    const SW_SHOWNORMAL: i32 = 1;
    let operation: Vec<u16> = "open\0".encode_utf16().collect();
    let file: Vec<u16> = target.encode_utf16().chain([0]).collect();
    let result = unsafe {
        ShellExecuteW(
            std::ptr::null_mut(),
            operation.as_ptr(),
            file.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            SW_SHOWNORMAL,
        )
    };
    if result as isize > 32 {
        Ok(())
    } else {
        Err(format!(
            "не удалось открыть: ShellExecuteW вернул {:?}",
            result
        ))
    }
}

pub fn scan_mods(dir: &Path, metadata: &[DllMeta]) -> Result<Vec<ModEntry>, String> {
    if !dir.exists() {
        return Ok(Vec::new());
    }
    let mut mods = Vec::new();
    let entries =
        fs::read_dir(dir).map_err(|error| format!("не удалось прочитать каталог: {error}"))?;
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let name = path
            .file_name()
            .map(|value| value.to_string_lossy().to_string())
            .unwrap_or_default();
        let lowered = name.to_ascii_lowercase();
        let kind = if lowered.ends_with(".zip") {
            "zip"
        } else if lowered.ends_with(".dll") {
            "dll"
        } else {
            continue;
        };
        let size = entry.metadata().map(|meta| meta.len()).unwrap_or(0);
        let meta = metadata
            .iter()
            .find(|meta| meta.file_name.eq_ignore_ascii_case(&name));
        mods.push(ModEntry {
            file_name: name,
            path: path.display().to_string(),
            size,
            kind: kind.to_string(),
            name: meta
                .map(|meta| meta.name.clone())
                .filter(|value| !value.trim().is_empty())
                .unwrap_or_default(),
            description: meta
                .map(|meta| meta.description.clone())
                .filter(|value| !value.trim().is_empty())
                .unwrap_or_default(),
            version: meta
                .map(|meta| meta.version.clone())
                .filter(|value| !value.trim().is_empty())
                .unwrap_or_default(),
            game: meta.map(|meta| meta.game).unwrap_or(false),
            preload: meta.map(|meta| meta.preload).unwrap_or(false),
        });
    }
    mods.sort_by(|left, right| left.file_name.cmp(&right.file_name));
    Ok(mods)
}

pub fn read_dll_metadata(loader: &Path, dir: &Path) -> Vec<DllMeta> {
    if !loader.exists() {
        return Vec::new();
    }
    let output = match Command::new(loader).arg("scan-mods").arg(dir).output() {
        Ok(value) if value.status.success() => value,
        _ => return Vec::new(),
    };
    let raw = String::from_utf8_lossy(&output.stdout);
    serde_json::from_str::<Vec<DllMeta>>(raw.trim()).unwrap_or_default()
}

pub fn clear_cache() -> Result<(), String> {
    let root = dirs::cache_dir()
        .map(|dir| dir.join("illusio"))
        .ok_or_else(|| "не удалось определить каталог кэша".to_string())?;
    if !root.exists() {
        return Ok(());
    }
    fs::remove_dir_all(&root).map_err(|error| format!("не удалось очистить кэш: {error}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scans_zip_and_dll_files() {
        let dir = std::env::temp_dir().join(format!("illusio-mods-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        fs::File::create(dir.join("pack_a.zip")).unwrap();
        fs::File::create(dir.join("notes.txt")).unwrap();
        fs::File::create(dir.join("PACK_B.ZIP")).unwrap();
        fs::File::create(dir.join("half.dll")).unwrap();
        let metadata = vec![DllMeta {
            file_name: "half.dll".into(),
            name: "Half Life".into(),
            description: "раз".into(),
            version: "1.0".into(),
            ..DllMeta::default()
        }];
        let mods = scan_mods(&dir, &metadata).unwrap();
        assert_eq!(mods.len(), 3);
        assert_eq!(mods[0].file_name, "PACK_B.ZIP");
        assert_eq!(mods[0].kind, "zip");
        let dll = mods
            .iter()
            .find(|mod_entry| mod_entry.kind == "dll")
            .unwrap();
        assert_eq!(dll.name, "Half Life");
        assert_eq!(dll.version, "1.0");
        fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn missing_dir_is_empty() {
        let dir = std::env::temp_dir().join("illusio-no-such-mods-dir");
        assert!(scan_mods(&dir, &[]).unwrap().is_empty());
    }

    #[test]
    fn validates_http_urls() {
        assert!(super::is_http_url("https://example.com"));
        assert!(super::is_http_url("HTTP://EXAMPLE.COM/path"));
        assert!(super::is_http_url("  https://example.com  "));
        assert!(!super::is_http_url("ftp://example.com"));
        assert!(!super::is_http_url("file:///etc/passwd"));
        assert!(!super::is_http_url("javascript:alert(1)"));
        assert!(!super::is_http_url("example.com"));
        assert!(!super::is_http_url("https://"));
        assert!(!super::is_http_url(""));
    }

    #[test]
    fn open_rejects_non_http_targets() {
        assert!(open_with_system("file:///etc/passwd").is_err());
        assert!(open_with_system("C:\\Windows\\System32").is_err());
        assert!(open_with_system("calc.exe").is_err());
        assert!(open_path("").is_err());
    }

    #[test]
    fn metadata_survives_bad_output() {
        let dir = std::env::temp_dir().join("illusio-no-loader-here");
        assert!(read_dll_metadata(&PathBuf::from("/nonexistent/loader"), &dir).is_empty());
    }
}

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
}

pub fn ensure_dir(path: &Path) -> Result<PathBuf, String> {
    fs::create_dir_all(path).map_err(|error| format!("не удалось создать каталог: {error}"))?;
    Ok(path.to_path_buf())
}

pub fn open_with_system(target: &str) -> Result<(), String> {
    let mut command = if cfg!(target_os = "windows") {
        let mut command = Command::new("cmd");
        command.args(["/C", "start", "", target]);
        command
    } else if cfg!(target_os = "macos") {
        let mut command = Command::new("open");
        command.arg(target);
        command
    } else {
        let mut command = Command::new("xdg-open");
        command.arg(target);
        command
    };
    command
        .spawn()
        .map(|_| ())
        .map_err(|error| format!("не удалось открыть: {error}"))
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
    fn metadata_survives_bad_output() {
        let dir = std::env::temp_dir().join("illusio-no-loader-here");
        assert!(read_dll_metadata(&PathBuf::from("/nonexistent/loader"), &dir).is_empty());
    }
}

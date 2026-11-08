use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, Default, Serialize)]
pub struct ModEntry {
    pub file_name: String,
    pub path: String,
    pub size: u64,
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

pub fn scan_mods(dir: &Path) -> Result<Vec<ModEntry>, String> {
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
        if !name.to_ascii_lowercase().ends_with(".zip") {
            continue;
        }
        let size = entry.metadata().map(|meta| meta.len()).unwrap_or(0);
        mods.push(ModEntry {
            file_name: name,
            path: path.display().to_string(),
            size,
        });
    }
    mods.sort_by(|left, right| left.file_name.cmp(&right.file_name));
    Ok(mods)
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
    fn scans_only_zip_files() {
        let dir = std::env::temp_dir().join(format!("illusio-mods-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        fs::File::create(dir.join("pack_a.zip")).unwrap();
        fs::File::create(dir.join("notes.txt")).unwrap();
        fs::File::create(dir.join("PACK_B.ZIP")).unwrap();
        let mods = scan_mods(&dir).unwrap();
        assert_eq!(mods.len(), 2);
        assert_eq!(mods[0].file_name, "PACK_B.ZIP");
        fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn missing_dir_is_empty() {
        let dir = std::env::temp_dir().join("illusio-no-such-mods-dir");
        assert!(scan_mods(&dir).unwrap().is_empty());
    }
}

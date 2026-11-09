use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

use crate::config;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CustomEngine {
    pub id: String,
    pub name: String,
    pub version: String,
    #[serde(rename = "fileName")]
    pub file_name: String,
}

#[derive(Debug, Deserialize)]
struct EngineMeta {
    #[serde(default)]
    name: String,
    #[serde(default)]
    version: String,
}

pub fn engines_dir() -> Option<PathBuf> {
    config::config_dir().map(|dir| dir.join("engines"))
}

fn slug(raw: &str) -> String {
    let filtered: String = raw
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() {
                character.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect();
    let trimmed = filtered.trim_matches('-');
    if trimmed.is_empty() {
        "engine".to_string()
    } else {
        trimmed.to_string()
    }
}

pub fn list() -> Vec<CustomEngine> {
    list_in(engines_dir())
}

pub fn list_in(dir: Option<PathBuf>) -> Vec<CustomEngine> {
    let Some(dir) = dir else {
        return Vec::new();
    };
    let Ok(entries) = fs::read_dir(&dir) else {
        return Vec::new();
    };
    let mut engines = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let Ok(raw) = fs::read_to_string(&path) else {
            continue;
        };
        let Ok(engine) = serde_json::from_str::<CustomEngine>(&raw) else {
            continue;
        };
        if engine.id.is_empty() || engine.file_name.contains('/') || engine.file_name.contains('\\')
        {
            continue;
        }
        if !dir.join(&engine.file_name).exists() {
            continue;
        }
        engines.push(engine);
    }
    engines.sort_by(|left, right| left.name.cmp(&right.name));
    engines
}

pub fn import(source: &Path) -> Result<CustomEngine, String> {
    let dir = engines_dir().ok_or("не удалось определить каталог движков")?;
    import_in(&dir, source)
}

pub fn import_in(dir: &Path, source: &Path) -> Result<CustomEngine, String> {
    let source = source
        .canonicalize()
        .map_err(|error| format!("не удалось открыть источник: {error}"))?;
    fs::create_dir_all(dir).map_err(|error| error.to_string())?;

    let stem = source
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("engine")
        .to_string();

    let meta = if source.is_dir() {
        read_folder(&source, &stem)?
    } else {
        read_zip(&source, &stem)?
    };

    let mut id = slug(&meta.name);
    let mut counter = 1;
    while dir.join(format!("{id}.json")).exists() {
        counter += 1;
        id = format!("{}-{counter}", slug(&meta.name));
    }

    let zip_name = format!("{id}.zip");
    let dest = dir.join(&zip_name);
    if source.is_dir() {
        zip_folder(&source, &dest)?;
    } else {
        fs::copy(&source, &dest).map_err(|error| error.to_string())?;
    }

    let engine = CustomEngine {
        id,
        name: meta.name,
        version: meta.version,
        file_name: zip_name,
    };
    let manifest = serde_json::to_string_pretty(&engine).map_err(|error| error.to_string())?;
    fs::write(dir.join(format!("{}.json", engine.id)), manifest)
        .map_err(|error| error.to_string())?;
    Ok(engine)
}

pub fn remove(id: &str) -> Result<(), String> {
    let dir = engines_dir().ok_or("не удалось определить каталог движков")?;
    remove_in(&dir, id)
}

pub fn remove_in(dir: &Path, id: &str) -> Result<(), String> {
    let id = id.trim();
    if id.is_empty() || id.contains('/') || id.contains('\\') || id.contains("..") {
        return Err("некорректный идентификатор движка".into());
    }

    let manifest = dir.join(format!("{id}.json"));
    let zip = dir.join(format!("{id}.zip"));
    if !manifest.exists() && !zip.exists() {
        return Err("движок не найден".into());
    }

    if manifest.exists() {
        fs::remove_file(&manifest).map_err(|error| error.to_string())?;
    }
    if zip.exists() {
        fs::remove_file(&zip).map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn read_folder(source: &Path, stem: &str) -> Result<EngineMeta, String> {
    if !source.join("Robust.Client.dll").exists() {
        return Err("в каталоге нет Robust.Client.dll".into());
    }

    let meta_path = source.join("engine.json");
    let meta = match fs::read_to_string(&meta_path) {
        Ok(raw) => serde_json::from_str::<EngineMeta>(&raw)
            .map_err(|error| format!("битый engine.json: {error}"))?,
        Err(_) => EngineMeta {
            name: stem.to_string(),
            version: String::new(),
        },
    };
    Ok(finish_meta(meta, stem))
}

fn read_zip(source: &Path, stem: &str) -> Result<EngineMeta, String> {
    let file = fs::File::open(source).map_err(|error| error.to_string())?;
    let mut archive = zip::ZipArchive::new(file).map_err(|error| error.to_string())?;

    let has_client = archive
        .file_names()
        .any(|name| name == "Robust.Client.dll" || name.ends_with("/Robust.Client.dll"));
    if !has_client {
        return Err("в архиве нет Robust.Client.dll".into());
    }

    let mut meta = EngineMeta {
        name: stem.to_string(),
        version: String::new(),
    };
    for index in 0..archive.len() {
        let Ok(mut entry) = archive.by_index(index) else {
            continue;
        };
        let name = entry.name().to_string();
        let trimmed = name.trim_start_matches('/');
        if trimmed != "engine.json" {
            continue;
        }

        let mut raw = String::new();
        if entry.read_to_string(&mut raw).is_ok() {
            if let Ok(parsed) = serde_json::from_str::<EngineMeta>(&raw) {
                meta = parsed;
            }
        }
        break;
    }
    Ok(finish_meta(meta, stem))
}

fn finish_meta(meta: EngineMeta, stem: &str) -> EngineMeta {
    let name = meta.name.trim();
    EngineMeta {
        name: if name.is_empty() {
            stem.to_string()
        } else {
            name.to_string()
        },
        version: meta.version.trim().to_string(),
    }
}

fn zip_folder(source: &Path, dest: &Path) -> Result<(), String> {
    let file = fs::File::create(dest).map_err(|error| error.to_string())?;
    let mut archive = zip::ZipWriter::new(file);
    let options: zip::write::SimpleFileOptions = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);

    let mut stack = vec![source.to_path_buf()];
    while let Some(current) = stack.pop() {
        let entries = fs::read_dir(&current).map_err(|error| error.to_string())?;
        for entry in entries.flatten() {
            let path = entry.path();
            let name = path
                .strip_prefix(source)
                .map_err(|error| error.to_string())?
                .components()
                .map(|component| component.as_os_str().to_string_lossy().to_string())
                .collect::<Vec<_>>()
                .join("/");
            if path.is_dir() {
                archive
                    .add_directory(&name, options)
                    .map_err(|error| error.to_string())?;
                stack.push(path);
            } else {
                archive
                    .start_file(&name, options)
                    .map_err(|error| error.to_string())?;
                let mut file = fs::File::open(&path).map_err(|error| error.to_string())?;
                std::io::copy(&mut file, &mut archive)
                    .map_err(|error: std::io::Error| error.to_string())?;
            }
        }
    }

    archive.finish().map_err(|error| error.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slugifies_names() {
        assert_eq!(slug("My Cool Engine"), "my-cool-engine");
        assert_eq!(slug("///"), "engine");
    }

    #[test]
    fn imports_and_removes_folder_engine() {
        let base = std::env::temp_dir().join(format!("illusio-engines-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let source = base.join("source");
        fs::create_dir_all(source.join("bin")).unwrap();
        fs::write(source.join("Robust.Client.dll"), "client").unwrap();
        fs::write(
            source.join("engine.json"),
            r#"{"name":"Test Fork","version":"240.0.0"}"#,
        )
        .unwrap();

        let dir = base.join("config").join("engines");
        let engine = import_in(&dir, &source).unwrap();
        assert_eq!(engine.name, "Test Fork");
        assert_eq!(engine.version, "240.0.0");
        assert!(dir.join(&engine.file_name).exists());
        assert!(list_in(Some(dir.clone()))
            .iter()
            .any(|value| value.id == engine.id));

        remove_in(&dir, &engine.id).unwrap();
        assert!(!list_in(Some(dir.clone()))
            .iter()
            .any(|value| value.id == engine.id));
        let _ = fs::remove_dir_all(&base);
    }

    #[test]
    fn rejects_zip_without_client() {
        let base = std::env::temp_dir().join(format!("illusio-engines-bad-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        fs::create_dir_all(&base).unwrap();
        let dir = base.join("engines");
        let zip_path = base.join("empty.zip");
        let file = fs::File::create(&zip_path).unwrap();
        let mut writer = zip::ZipWriter::new(file);
        writer
            .start_file("readme.txt", zip::write::SimpleFileOptions::default())
            .unwrap();
        std::io::Write::write_all(&mut writer, b"nothing").unwrap();
        writer.finish().unwrap();

        let error = import_in(&dir, &zip_path).unwrap_err();
        assert!(error.contains("Robust.Client.dll"));
        let _ = fs::remove_dir_all(&base);
    }
}

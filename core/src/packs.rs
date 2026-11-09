use serde::Serialize;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Default, Serialize)]
pub struct ResPackInfo {
    pub dir_name: String,
    pub path: String,
    pub name: String,
    pub description: String,
    pub target: String,
    pub files: u64,
    pub size: u64,
    pub valid: bool,
}

#[derive(Debug, Clone, Default, serde::Deserialize)]
struct PackMeta {
    #[serde(default, alias = "Name")]
    name: String,
    #[serde(default, alias = "Description")]
    description: String,
    #[serde(default, alias = "Target")]
    target: String,
}

pub fn list_packs(dir: &Path) -> Vec<ResPackInfo> {
    let mut packs = Vec::new();
    let entries = match fs::read_dir(dir) {
        Ok(value) => value,
        Err(_) => return packs,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let meta_path = path.join("meta.json");
        let mut info = ResPackInfo {
            dir_name: path
                .file_name()
                .map(|value| value.to_string_lossy().to_string())
                .unwrap_or_default(),
            path: path.display().to_string(),
            ..ResPackInfo::default()
        };
        if let Ok(raw) = fs::read_to_string(&meta_path) {
            if let Ok(meta) = serde_json::from_str::<PackMeta>(&raw) {
                info.name = meta.name.trim().to_string();
                info.description = meta.description.trim().to_string();
                info.target = meta.target.trim().to_string();
                info.valid = !info.name.is_empty();
            }
        }
        if let Ok(entries) = fs::read_dir(&path) {
            for file in entries.flatten() {
                walk_pack(&file.path(), &mut info);
            }
        }
        packs.push(info);
    }
    packs.sort_by(|left, right| left.dir_name.cmp(&right.dir_name));
    packs
}

fn walk_pack(path: &Path, info: &mut ResPackInfo) {
    if path.is_dir() {
        if let Ok(entries) = fs::read_dir(path) {
            for entry in entries.flatten() {
                walk_pack(&entry.path(), info);
            }
        }
        return;
    }
    if !path.is_file() {
        return;
    }
    let is_meta = path
        .file_name()
        .map(|name| name.to_string_lossy().eq_ignore_ascii_case("meta.json"))
        == Some(true);
    if is_meta {
        return;
    }
    info.size += path.metadata().map(|meta| meta.len()).unwrap_or(0);
    info.files += 1;
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn lists_valid_and_invalid_packs() {
        let root = std::env::temp_dir().join(format!("illusio-packs-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let valid = root.join("HiTech");
        fs::create_dir_all(valid.join("Textures")).unwrap();
        fs::write(
            valid.join("meta.json"),
            r#"{"Name":"HiTech","Description":"replaces textures","Target":"hitech_fork"}"#,
        )
        .unwrap();
        fs::write(valid.join("Textures").join("flag.png"), [1u8, 2, 3]).unwrap();
        fs::write(valid.join("meta.json.bak"), [1u8]).unwrap();
        let broken = root.join("Broken");
        fs::create_dir_all(&broken).unwrap();
        let empty = root.join("EmptyPack");
        fs::create_dir_all(&empty).unwrap();

        let packs = list_packs(&root);
        assert_eq!(packs.len(), 3);
        let hi = packs.iter().find(|pack| pack.dir_name == "HiTech").unwrap();
        assert!(hi.valid);
        assert_eq!(hi.name, "HiTech");
        assert_eq!(hi.target, "hitech_fork");
        assert_eq!(hi.files, 2);
        assert_eq!(hi.size, 4);
        let broken = packs.iter().find(|pack| pack.dir_name == "Broken").unwrap();
        assert!(!broken.valid);
        assert_eq!(broken.files, 0);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn missing_dir_is_empty() {
        assert!(list_packs(&PathBuf::from("/nonexistent-illusio-packs")).is_empty());
    }
}

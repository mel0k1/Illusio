use serde::Deserialize;
use std::fs;
use std::io::Read;
use std::path::Path;

#[derive(Debug, Deserialize, Default)]
struct ModulesFile {
    #[serde(default)]
    modules: std::collections::BTreeMap<String, serde_json::Value>,
}

pub fn read_names(path: &Path) -> Result<Vec<String>, String> {
    let file =
        fs::File::open(path).map_err(|error| format!("не удалось открыть движок: {error}"))?;
    let mut archive =
        zip::ZipArchive::new(file).map_err(|error| format!("архив движка повреждён: {error}"))?;
    let raw = read_modules_json(&mut archive)?;
    let parsed: ModulesFile =
        serde_json::from_str(&raw).map_err(|error| format!("битый modules.json: {error}"))?;
    let names: Vec<String> = parsed
        .modules
        .keys()
        .map(|name| name.trim().to_string())
        .filter(|name| !name.is_empty())
        .collect();
    Ok(names)
}

fn read_modules_json(archive: &mut zip::ZipArchive<fs::File>) -> Result<String, String> {
    for index in 0..archive.len() {
        let mut entry = archive
            .by_index(index)
            .map_err(|error| format!("архив движка повреждён: {error}"))?;
        let name = entry.name().trim_start_matches('/');
        if name != "modules.json" {
            continue;
        }
        let mut raw = String::new();
        entry
            .read_to_string(&mut raw)
            .map_err(|error| format!("не удалось прочитать modules.json: {error}"))?;
        return Ok(raw);
    }
    Err("в архиве движка нет modules.json".into())
}

pub fn env_key(name: &str) -> String {
    let upper: String = name
        .trim()
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() {
                character.to_ascii_uppercase()
            } else {
                '_'
            }
        })
        .collect();
    format!("ROBUST_MODULE_{}", upper)
}

pub fn env_pairs(names: &[String]) -> Vec<(String, String)> {
    let mut pairs: Vec<(String, String)> = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for name in names {
        let trimmed = name.trim();
        if trimmed.is_empty() || !seen.insert(trimmed.to_string()) {
            continue;
        }
        pairs.push((env_key(trimmed), trimmed.to_string()));
    }
    pairs
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn maps_env_keys() {
        assert_eq!(env_key("Robust.Client"), "ROBUST_MODULE_ROBUST_CLIENT");
        assert_eq!(
            env_key("Robust.Client.WebView"),
            "ROBUST_MODULE_ROBUST_CLIENT_WEBVIEW"
        );
        assert_eq!(env_key(" CONTENT client "), "ROBUST_MODULE_CONTENT_CLIENT");
    }

    #[test]
    fn builds_unique_pairs() {
        let names = vec![
            "Robust.Client".to_string(),
            " ".to_string(),
            "Robust.Client".to_string(),
            "Robust.Shared".to_string(),
        ];
        let pairs = env_pairs(&names);
        assert_eq!(
            pairs,
            vec![
                (
                    "ROBUST_MODULE_ROBUST_CLIENT".to_string(),
                    "Robust.Client".to_string()
                ),
                (
                    "ROBUST_MODULE_ROBUST_SHARED".to_string(),
                    "Robust.Shared".to_string()
                ),
            ]
        );
    }

    #[test]
    fn reads_modules_json_from_zip() {
        let dir = std::env::temp_dir().join(format!("illusio-modules-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let zip_path = dir.join("engine.zip");
        let file = fs::File::create(&zip_path).unwrap();
        let mut archive = zip::ZipWriter::new(file);
        let options: zip::write::SimpleFileOptions = zip::write::SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated);
        archive.start_file("modules.json", options).unwrap();
        archive
            .write_all(
                br#"{"modules":{"Robust.Client":{"copyToRoot":true},"Robust.Shared":{"copyToRoot":true},"Robust.Client.WebView":{}}}"#,
            )
            .unwrap();
        archive.start_file("Robust.Client.dll", options).unwrap();
        archive.write_all(b"dll").unwrap();
        archive.finish().unwrap();

        let names = read_names(&zip_path).unwrap();
        assert_eq!(
            names,
            vec![
                "Robust.Client".to_string(),
                "Robust.Client.WebView".to_string(),
                "Robust.Shared".to_string(),
            ]
        );

        let broken = dir.join("broken.zip");
        fs::write(&broken, b"not a zip").unwrap();
        assert!(read_names(&broken).is_err());

        let empty = dir.join("empty.zip");
        let file = fs::File::create(&empty).unwrap();
        let mut archive = zip::ZipWriter::new(file);
        archive.start_file("Robust.Client.dll", options).unwrap();
        archive.write_all(b"dll").unwrap();
        archive.finish().unwrap();
        assert!(read_names(&empty).is_err());

        let _ = fs::remove_dir_all(&dir);
    }
}

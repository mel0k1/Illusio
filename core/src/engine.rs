use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::Duration;

pub const ENGINE_MANIFEST_URL: &str = "https://robust-builds.cdn.spacestation14.com/manifest.json";

#[derive(Debug, Clone, Deserialize, Default)]
pub struct EnginePlatform {
    #[serde(default)]
    pub url: String,
    #[serde(default, rename = "sha256")]
    pub sha256: String,
    #[serde(default)]
    pub sig: String,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct EngineVersion {
    #[serde(default)]
    pub insecure: bool,
    #[serde(default, rename = "redirect")]
    pub redirect_version: Option<String>,
    #[serde(default)]
    pub platforms: HashMap<String, EnginePlatform>,
}

pub type EngineManifest = HashMap<String, EngineVersion>;

fn client() -> Result<reqwest::blocking::Client, String> {
    crate::http::with_route(reqwest::blocking::Client::builder(), crate::http::Route::Region)
        .timeout(Duration::from_secs(20))
        .build()
        .map_err(|error| error.to_string())
}

pub fn fetch_engine_manifest() -> Result<EngineManifest, String> {
    let client = client()?;
    let response = client
        .get(ENGINE_MANIFEST_URL)
        .send()
        .map_err(|error| error.to_string())?;
    let response = response
        .error_for_status()
        .map_err(|error| format!("манифест движков: {error}"))?;
    response
        .json::<EngineManifest>()
        .map_err(|error| format!("не удалось разобрать манифест движков: {error}"))
}

pub fn engine_rid_candidates() -> Vec<&'static str> {
    let arm = cfg!(target_arch = "aarch64");
    if cfg!(target_os = "windows") {
        if arm {
            vec!["win-arm64", "win-x64"]
        } else {
            vec!["win-x64"]
        }
    } else if cfg!(target_os = "macos") {
        if arm {
            vec!["osx-arm64", "osx-x64"]
        } else {
            vec!["osx-x64"]
        }
    } else if arm {
        vec!["linux-arm64"]
    } else {
        vec!["linux-x64"]
    }
}

pub fn find_engine<'a>(
    manifest: &'a EngineManifest,
    version: &str,
) -> Result<(String, &'static str, &'a EnginePlatform), String> {
    let mut current = version.trim().to_string();
    let mut visited = 0;
    loop {
        let info = manifest
            .get(&current)
            .ok_or_else(|| format!("версия движка {current} не найдена в манифесте"))?;
        if info.insecure {
            return Err(format!("версия движка {current} помечена как небезопасная"));
        }
        match info.redirect_version.as_deref() {
            Some(next) if !next.is_empty() => {
                visited += 1;
                if visited > 10 {
                    return Err("слишком длинная цепочка перенаправлений версий движка".into());
                }
                current = next.to_string();
            }
            _ => {
                for rid in engine_rid_candidates() {
                    if let Some(platform) = info.platforms.get(rid) {
                        return Ok((current, rid, platform));
                    }
                }
                return Err(format!(
                    "для платформы нет сборки движка {current} (доступны: {:?})",
                    info.platforms.keys().collect::<Vec<_>>()
                ));
            }
        }
    }
}

pub fn engine_cache_path(engine_root: &Path, version: &str, rid: &str) -> PathBuf {
    engine_root.join(format!("{}-{}.zip", sanitize_engine_version(version), rid))
}

pub fn sanitize_engine_version(value: &str) -> String {
    let cleaned: String = value
        .trim()
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect();
    if cleaned.is_empty() {
        "unknown".into()
    } else {
        cleaned
    }
}

pub fn verify_engine_zip(path: &Path, expected_sha256: &str) -> Result<bool, String> {
    if !path.exists() {
        return Ok(false);
    }
    let mut file = fs::File::open(path).map_err(|error| error.to_string())?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 65536];
    loop {
        let read = file.read(&mut buffer).map_err(|error| error.to_string())?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    let digest = format!("{:x}", hasher.finalize());
    Ok(digest.eq_ignore_ascii_case(expected_sha256.trim()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn follows_redirects_and_picks_rid() {
        let mut manifest = EngineManifest::new();
        manifest.insert(
            "100.0.0".into(),
            EngineVersion {
                redirect_version: Some("100.0.1".into()),
                ..EngineVersion::default()
            },
        );
        manifest.insert(
            "100.0.1".into(),
            EngineVersion {
                insecure: false,
                platforms: {
                    let mut map = HashMap::new();
                    map.insert(
                        "linux-x64".into(),
                        EnginePlatform {
                            url: "https://cdn.example.com/linux.zip".into(),
                            sha256: "abc".into(),
                            sig: "sig".into(),
                        },
                    );
                    map.insert(
                        "win-x64".into(),
                        EnginePlatform {
                            url: "https://cdn.example.com/win.zip".into(),
                            sha256: "def".into(),
                            sig: "sig2".into(),
                        },
                    );
                    map
                },
                ..EngineVersion::default()
            },
        );
        let (version, _rid, platform) = find_engine(&manifest, "100.0.0").expect("found");
        assert_eq!(version, "100.0.1");
        if cfg!(target_os = "windows") {
            assert_eq!(platform.url, "https://cdn.example.com/win.zip");
        } else {
            assert_eq!(platform.url, "https://cdn.example.com/linux.zip");
        }
    }

    #[test]
    fn rejects_insecure_and_missing() {
        let mut manifest = EngineManifest::new();
        manifest.insert(
            "1.0".into(),
            EngineVersion {
                insecure: true,
                ..EngineVersion::default()
            },
        );
        assert!(find_engine(&manifest, "1.0").is_err());
        assert!(find_engine(&manifest, "9.9").is_err());
    }

    #[test]
    fn sanitizes_versions() {
        assert_eq!(sanitize_engine_version(" 240.1.0.5 "), "240.1.0.5");
        assert_eq!(sanitize_engine_version("a/b\\c"), "a_b_c");
    }
}

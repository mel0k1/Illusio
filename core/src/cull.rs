use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

use crate::config::Config;
use crate::engine;
use crate::install;

const DAY: Duration = Duration::from_secs(86_400);

pub struct CullReport {
    pub files: u64,
    pub bytes: u64,
}

struct Removals {
    files: u64,
    bytes: u64,
}

impl Removals {
    fn new() -> Removals {
        Removals { files: 0, bytes: 0 }
    }

    fn add(&mut self, path: &Path) {
        let size = fs::metadata(path).map(|meta| meta.len()).unwrap_or(0);
        if fs::remove_file(path).is_ok() {
            self.files += 1;
            self.bytes += size;
        }
    }
}

fn older_than(path: &Path, age: Duration) -> bool {
    match fs::metadata(path).and_then(|meta| meta.modified()) {
        Ok(modified) => modified
            .elapsed()
            .map(|elapsed| elapsed >= age)
            .unwrap_or(false),
        Err(_) => true,
    }
}

fn referenced_blobs(root: &Path) -> HashSet<String> {
    let mut set = HashSet::new();
    let entries = match fs::read_dir(root) {
        Ok(value) => value,
        Err(_) => return set,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let list = path.join("blobs.txt");
        let raw = match fs::read_to_string(&list) {
            Ok(value) => value,
            Err(_) => continue,
        };
        for line in raw.lines() {
            let hash = line.trim().to_ascii_lowercase();
            if hash.len() >= 16 {
                set.insert(hash);
            }
        }
    }
    set
}

fn referenced_engines(root: &Path) -> HashSet<String> {
    let mut set = HashSet::new();
    let entries = match fs::read_dir(root) {
        Ok(value) => value,
        Err(_) => return set,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let marker = match install::read_marker(&path) {
            Some(value) => value,
            None => continue,
        };
        let version = marker.engine_version.trim();
        if version.is_empty() {
            continue;
        }
        let sanitized = engine::sanitize_engine_version(version);
        for rid in engine::engine_rid_candidates() {
            set.insert(format!("{sanitized}-{rid}"));
        }
    }
    set
}

fn cull_blobs(cache: &Path, referenced: &HashSet<String>, keep_days: i64, out: &mut Removals) {
    let age = Duration::from_secs((keep_days.clamp(1, 90) as u64) * 86_400);
    let blobs = cache.join("blobs");
    let forks = match fs::read_dir(&blobs) {
        Ok(value) => value,
        Err(_) => return,
    };
    for fork in forks.flatten() {
        let fork_path = fork.path();
        if !fork_path.is_dir() {
            continue;
        }
        let files = match fs::read_dir(&fork_path) {
            Ok(value) => value,
            Err(_) => continue,
        };
        for file in files.flatten() {
            let path = file.path();
            let name = file.file_name().to_string_lossy().to_string();
            if name.ends_with(".bin") {
                let hash = name.trim_end_matches(".bin").to_ascii_lowercase();
                if referenced.contains(&hash) {
                    continue;
                }
                if older_than(&path, age) {
                    out.add(&path);
                }
                continue;
            }
            if (name.ends_with(".part") || name.ends_with(".tmp")) && older_than(&path, DAY) {
                out.add(&path);
            }
        }
        if fs::read_dir(&fork_path)
            .map(|value| value.count())
            .unwrap_or(1)
            == 0
        {
            fs::remove_dir(&fork_path).ok();
        }
    }
}

fn cull_engines(root: &Path, referenced: &HashSet<String>, keep: i64, out: &mut Removals) {
    let engines = root.join("engine");
    let mut stale: Vec<(PathBuf, std::time::SystemTime)> = Vec::new();
    let files = match fs::read_dir(&engines) {
        Ok(value) => value,
        Err(_) => return,
    };
    for file in files.flatten() {
        let path = file.path();
        let name = file.file_name().to_string_lossy().to_string();
        if name.ends_with(".zip") {
            let stem = name.trim_end_matches(".zip").to_string();
            if referenced.contains(&stem) {
                continue;
            }
            let modified = fs::metadata(&path)
                .and_then(|meta| meta.modified())
                .unwrap_or(std::time::SystemTime::UNIX_EPOCH);
            stale.push((path, modified));
            continue;
        }
        if (name.ends_with(".tmp") || name.ends_with(".url")) && older_than(&path, DAY) {
            out.add(&path);
        }
    }
    if stale.len() <= keep.max(0) as usize {
        return;
    }
    stale.sort_by_key(|(_, modified)| *modified);
    let excess = stale.len() - keep.max(0) as usize;
    for (path, _) in stale.into_iter().take(excess) {
        out.add(&path);
    }
}

fn cull_bundles(root: &Path, keep: i64, out: &mut Removals) {
    let bundles = root.join("bundles");
    let mut zips: Vec<(PathBuf, std::time::SystemTime)> = Vec::new();
    let dirs = match fs::read_dir(&bundles) {
        Ok(value) => value,
        Err(_) => return,
    };
    for dir in dirs.flatten() {
        let dir_path = dir.path();
        if !dir_path.is_dir() {
            continue;
        }
        let files = match fs::read_dir(&dir_path) {
            Ok(value) => value,
            Err(_) => continue,
        };
        for file in files.flatten() {
            let path = file.path();
            let name = file.file_name().to_string_lossy().to_string();
            if name.ends_with(".zip") {
                let modified = fs::metadata(&path)
                    .and_then(|meta| meta.modified())
                    .unwrap_or(std::time::SystemTime::UNIX_EPOCH);
                zips.push((path, modified));
            } else if (name.ends_with(".tmp") || name.ends_with(".url")) && older_than(&path, DAY) {
                out.add(&path);
            }
        }
    }
    if zips.len() <= keep.max(0) as usize {
        return;
    }
    zips.sort_by_key(|(_, modified)| *modified);
    let excess = zips.len() - keep.max(0) as usize;
    for (path, _) in zips.into_iter().take(excess) {
        out.add(&path);
    }
}

fn cull_temp(root: &Path, out: &mut Removals) {
    let entries = match fs::read_dir(root) {
        Ok(value) => value,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_string();
        if (name.ends_with(".tmp") || name.ends_with(".tmp.url") || name.ends_with(".url"))
            && older_than(&path, DAY)
        {
            out.add(&path);
        }
    }
}

pub fn cull(config: &Config) -> Result<CullReport, String> {
    let cache = dirs::cache_dir()
        .map(|dir| dir.join("illusio"))
        .ok_or_else(|| "не удалось определить каталог кэша".to_string())?;
    cull_in(config, &cache)
}

pub fn cull_in(config: &Config, cache: &Path) -> Result<CullReport, String> {
    let root = install::resolve_install_root(&config.install_dir)?;
    let mut out = Removals::new();
    let blobs = referenced_blobs(&root);
    let engines = referenced_engines(&root);
    cull_blobs(cache, &blobs, config.blob_keep_days, &mut out);
    cull_engines(&root, &engines, config.engine_keep, &mut out);
    cull_bundles(&root, config.bundle_keep, &mut out);
    cull_temp(&root, &mut out);
    cull_temp(&root.join("engine"), &mut out);
    Ok(CullReport {
        files: out.files,
        bytes: out.bytes,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_old(path: &Path, days: u64) {
        let file = fs::OpenOptions::new().append(true).open(path).unwrap();
        let past = std::time::SystemTime::now() - Duration::from_secs(days * 86_400);
        file.set_times(std::fs::FileTimes::new().set_modified(past))
            .unwrap();
    }

    #[test]
    fn cull_keeps_referenced_blobs() {
        let base = std::env::temp_dir().join(format!("illusio-cull-{}", std::process::id()));
        let root = base.join("install").join("client");
        let blobs = base.join("cache").join("blobs").join("fork");
        fs::create_dir_all(&root).unwrap();
        fs::create_dir_all(&blobs).unwrap();
        fs::write(root.join("blobs.txt"), "0123456789abcdef0123456789abcdef\n").unwrap();
        fs::write(blobs.join("0123456789abcdef0123456789abcdef.bin"), "x").unwrap();
        fs::write(blobs.join("fedcba9876543210fedcba9876543210.bin"), "y").unwrap();
        make_old(&blobs.join("fedcba9876543210fedcba9876543210.bin"), 2);
        let config = Config {
            install_dir: root.parent().unwrap().display().to_string(),
            blob_keep_days: 1,
            ..Config::default()
        };
        let report = cull_in(&config, &base.join("cache")).unwrap();
        assert_eq!(report.files, 1);
        assert!(blobs.join("0123456789abcdef0123456789abcdef.bin").exists());
        assert!(!blobs.join("fedcba9876543210fedcba9876543210.bin").exists());
        fs::remove_dir_all(base).ok();
    }

    #[test]
    fn cull_engines_keeps_newest() {
        let base = std::env::temp_dir().join(format!("illusio-cull-eng-{}", std::process::id()));
        let root = base.join("install");
        let engines = root.join("engine");
        fs::create_dir_all(&engines).unwrap();
        let rid = engine::engine_rid_candidates()[0];
        let old = format!("238.0.0.1-{rid}.zip");
        let middle = format!("239.0.0.1-{rid}.zip");
        let fresh = format!("240.1.0.5-{rid}.zip");
        fs::write(engines.join(&fresh), "a").unwrap();
        fs::write(engines.join(&middle), "b").unwrap();
        fs::write(engines.join(&old), "c").unwrap();
        make_old(&engines.join(&old), 3);
        let mut config = Config {
            install_dir: root.display().to_string(),
            engine_keep: 2,
            ..Config::default()
        };
        let report = cull_in(&config, &base.join("cache")).unwrap();
        assert_eq!(report.files, 1);
        assert!(!engines.join(&old).exists());
        assert!(engines.join(&middle).exists());
        assert!(engines.join(&fresh).exists());
        fs::create_dir_all(root.join("client")).unwrap();
        fs::write(
            root.join("client").join("version"),
            r#"{"version":"1","forkId":"f","hash":"","manifestHash":"","engineVersion":"239.0.0.1","acz":true}"#,
        )
        .unwrap();
        let report = cull_in(&config, &base.join("cache")).unwrap();
        assert_eq!(report.files, 0);
        config.engine_keep = 0;
        let report = cull_in(&config, &base.join("cache")).unwrap();
        assert_eq!(report.files, 1);
        assert!(engines.join(&middle).exists());
        fs::remove_dir_all(base).ok();
    }
}

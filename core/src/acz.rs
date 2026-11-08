use blake2::digest::consts::U32;
use blake2::{Blake2b, Digest};
use serde::Serialize;
use std::collections::HashSet;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::Duration;

const MANIFEST_HEADER: &str = "Robust Content Manifest 1";
const MANIFEST_TIMEOUT: Duration = Duration::from_secs(20);
const DOWNLOAD_PROTOCOL: i32 = 1;

#[derive(Debug, Clone, Serialize)]
pub struct ManifestEntry {
    pub index: usize,
    #[serde(rename = "hash")]
    pub hash_hex: String,
    pub path: String,
}

pub fn blake2b_hex(data: &[u8]) -> String {
    let mut hasher = Blake2b::<U32>::new();
    hasher.update(data);
    let digest = hasher.finalize();
    hex(&digest)
}

fn hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}

pub fn parse_manifest(text: &str) -> Result<Vec<ManifestEntry>, String> {
    let mut lines = text.lines();
    let header = lines.next().unwrap_or("").trim();
    if header != MANIFEST_HEADER {
        return Err("неизвестный формат манифеста контента".into());
    }
    let mut entries = Vec::new();
    for (index, line) in lines.enumerate() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let (hash, path) = line
            .split_once(' ')
            .ok_or_else(|| format!("битая строка манифеста: {index}"))?;
        let hash_hex = hash.trim().to_ascii_lowercase();
        if hash_hex.len() != 64 || !hash_hex.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(format!("битый хэш в манифесте: {index}"));
        }
        if path.is_empty() || path.starts_with('/') || path.contains("..") {
            return Err(format!("опасный путь в манифесте: {index}"));
        }
        entries.push(ManifestEntry {
            index,
            hash_hex,
            path: path.to_string(),
        });
    }
    if entries.is_empty() {
        return Err("манифест контента пуст".into());
    }
    Ok(entries)
}

pub fn fetch_manifest(manifest_url: &str) -> Result<(Vec<ManifestEntry>, String), String> {
    let client = crate::http::with_proxy(reqwest::blocking::Client::builder())
        .timeout(MANIFEST_TIMEOUT)
        .build()
        .map_err(|error| error.to_string())?;
    let response = client
        .get(manifest_url)
        .header("Accept-Encoding", "zstd")
        .send()
        .map_err(|error| error.to_string())?;
    let response = response
        .error_for_status()
        .map_err(|error| format!("манифест контента: {error}"))?;
    let compressed = response
        .headers()
        .get("Content-Encoding")
        .and_then(|value| value.to_str().ok())
        .map(|value| value.to_ascii_lowercase().contains("zstd"))
        .unwrap_or(false);
    let reader = response;
    let raw = if compressed {
        zstd::stream::decode_all(reader)
            .map_err(|error| format!("не удалось распаковать манифест: {error}"))?
    } else {
        let mut buffer = Vec::new();
        reader
            .take(64 * 1024 * 1024)
            .read_to_end(&mut buffer)
            .map_err(|error| error.to_string())?;
        buffer
    };
    let hash = blake2b_hex(&raw);
    let text =
        String::from_utf8(raw).map_err(|_| "манифест контента не является текстом".to_string())?;
    let entries = parse_manifest(&text)?;
    Ok((entries, hash))
}

pub fn blobs_dir(cache_root: &Path, fork: &str) -> PathBuf {
    cache_root.join("blobs").join(sanitize_dir_name(fork))
}

pub fn sanitize_dir_name(value: &str) -> String {
    let cleaned: String = value
        .trim()
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.' {
                c
            } else {
                '_'
            }
        })
        .collect();
    if cleaned.is_empty() {
        "content".into()
    } else {
        cleaned
    }
}

pub fn check_download_protocol(
    client: &reqwest::blocking::Client,
    url: &str,
) -> Result<(), String> {
    let response = client
        .request(reqwest::Method::OPTIONS, url)
        .send()
        .map_err(|error| error.to_string())?;
    let response = response
        .error_for_status()
        .map_err(|error| format!("сервер загрузки ответил с ошибкой: {error}"))?;
    let min = header_number(&response, "X-Robust-Download-Min-Protocol")?;
    let max = header_number(&response, "X-Robust-Download-Max-Protocol")?;
    if min > DOWNLOAD_PROTOCOL || max < DOWNLOAD_PROTOCOL {
        return Err(format!(
            "сервер загрузки не поддерживает протокол {DOWNLOAD_PROTOCOL} (доступно {min}-{max})"
        ));
    }
    Ok(())
}

fn header_number(response: &reqwest::blocking::Response, name: &str) -> Result<i32, String> {
    let value = response
        .headers()
        .get(name)
        .and_then(|value| value.to_str().ok())
        .ok_or_else(|| format!("в ответе нет заголовка {name}"))?;
    value
        .trim()
        .parse::<i32>()
        .map_err(|_| format!("некорректный заголовок {name}: {value}"))
}

pub struct BlobDownload {
    pub index: usize,
    pub hash_hex: String,
    pub data: Vec<u8>,
}

pub fn download_blobs(
    client: &reqwest::blocking::Client,
    url: &str,
    entries: &[ManifestEntry],
    mut on_blob: impl FnMut(&BlobDownload) -> Result<(), String>,
) -> Result<(), String> {
    let body = build_request_body(entries);
    let response = client
        .post(url)
        .header("X-Robust-Download-Protocol", DOWNLOAD_PROTOCOL.to_string())
        .header("Accept-Encoding", "zstd")
        .header("Content-Type", "application/octet-stream")
        .body(body)
        .send()
        .map_err(|error| error.to_string())?;
    let response = response
        .error_for_status()
        .map_err(|error| format!("загрузка файлов: {error}"))?;
    let compressed = response
        .headers()
        .get("Content-Encoding")
        .and_then(|value| value.to_str().ok())
        .map(|value| value.to_ascii_lowercase().contains("zstd"))
        .unwrap_or(false);
    let mut stream: Box<dyn Read> = if compressed {
        let decoder = zstd::stream::Decoder::new(response)
            .map_err(|error| format!("не удалось распаковать поток: {error}"))?;
        Box::new(decoder)
    } else {
        Box::new(response)
    };

    let mut flags = [0u8; 4];
    stream
        .read_exact(&mut flags)
        .map_err(|error| format!("обрыв потока загрузки: {error}"))?;
    let flags_value = i32::from_le_bytes(flags);
    let precompressed = flags_value & 1 != 0;

    let mut buffer: Vec<u8> = Vec::new();
    let mut compressed_buffer: Vec<u8> = Vec::new();
    let mut decompressed_buffer: Vec<u8> = Vec::new();
    for entry in entries {
        let mut length = [0u8; 4];
        stream
            .read_exact(&mut length)
            .map_err(|error| format!("обрыв потока загрузки: {error}"))?;
        let length_value = i32::from_le_bytes(length);
        if length_value < 0 {
            return Err("отрицательный размер файла в потоке".into());
        }
        buffer.clear();
        buffer.resize(length_value as usize, 0);
        stream
            .read_exact(&mut buffer)
            .map_err(|error| format!("обрыв потока загрузки: {error}"))?;
        if precompressed {
            let mut compressed_length = [0u8; 4];
            stream
                .read_exact(&mut compressed_length)
                .map_err(|error| format!("обрыв потока загрузки: {error}"))?;
            let compressed_value = i32::from_le_bytes(compressed_length);
            if compressed_value > 0 {
                compressed_buffer.clear();
                compressed_buffer.resize(compressed_value as usize, 0);
                stream
                    .read_exact(&mut compressed_buffer)
                    .map_err(|error| format!("обрыв потока загрузки: {error}"))?;
                decompressed_buffer.clear();
                decompressed_buffer.resize(length_value as usize, 0);
                let written = zstd::stream::Decoder::new(&compressed_buffer[..])
                    .and_then(|mut decoder| decoder.read_to_end(&mut decompressed_buffer))
                    .map_err(|error| format!("не удалось распаковать файл: {error}"))?;
                if written != length_value as usize {
                    return Err("размер распакованного файла не совпал".into());
                }
                buffer.copy_from_slice(&decompressed_buffer);
            }
        }
        let actual = blake2b_hex(&buffer);
        if actual != entry.hash_hex {
            return Err(format!("хэш файла {} не совпал", entry.path));
        }
        let blob = BlobDownload {
            index: entry.index,
            hash_hex: entry.hash_hex.clone(),
            data: buffer.clone(),
        };
        on_blob(&blob)?;
    }
    Ok(())
}

fn build_request_body(entries: &[ManifestEntry]) -> Vec<u8> {
    let mut body = Vec::with_capacity(entries.len() * 4);
    for entry in entries {
        body.extend_from_slice(&(entry.index as i32).to_le_bytes());
    }
    body
}

pub fn unique_entries(entries: &[ManifestEntry]) -> Vec<ManifestEntry> {
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for entry in entries {
        if seen.insert(entry.hash_hex.clone()) {
            out.push(entry.clone());
        }
    }
    out
}

pub fn assemble_overlay_zip(
    entries: &[ManifestEntry],
    blobs_dir: &Path,
    target: &Path,
    mut on_progress: impl FnMut(u64),
) -> Result<(), String> {
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let file = fs::File::create(target).map_err(|error| error.to_string())?;
    let mut writer = zip::ZipWriter::new(file);
    let options = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .large_file(true);
    let mut done: u64 = 0;
    for entry in entries {
        let blob_path = blobs_dir.join(format!("{}.bin", entry.hash_hex));
        let mut blob = fs::File::open(&blob_path)
            .map_err(|error| format!("нет файла в кэше: {}: {error}", entry.hash_hex))?;
        writer
            .start_file(entry.path.as_str(), options)
            .map_err(|error| format!("не удалось упаковать {}: {error}", entry.path))?;
        std::io::copy(&mut blob, &mut writer)
            .map_err(|error| format!("не удалось упаковать {}: {error}", entry.path))?;
        let size = blob.metadata().map(|m| m.len()).unwrap_or(0);
        done += size;
        on_progress(done);
    }
    writer.finish().map_err(|error| error.to_string())?;
    Ok(())
}

pub fn write_blob_cache(blobs_dir: &Path, hash_hex: &str, data: &[u8]) -> Result<PathBuf, String> {
    fs::create_dir_all(blobs_dir).map_err(|error| error.to_string())?;
    let path = blobs_dir.join(format!("{hash_hex}.bin"));
    fs::write(&path, data).map_err(|error| error.to_string())?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_A: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const SAMPLE_B: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

    fn sample_manifest() -> String {
        format!(
            "{MANIFEST_HEADER}\n{SAMPLE_A} Assemblies/Content.Client.dll\n{SAMPLE_B} Resources/Fonts/x.ttf\n\n"
        )
    }

    #[test]
    fn parses_manifest() {
        let entries = parse_manifest(&sample_manifest()).expect("parse");
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].index, 0);
        assert_eq!(entries[0].path, "Assemblies/Content.Client.dll");
        assert_eq!(entries[0].hash_hex, SAMPLE_A);
    }

    #[test]
    fn rejects_bad_manifests() {
        assert!(parse_manifest("Nope 1\n").is_err());
        assert!(parse_manifest("").is_err());
        let bad = format!("{MANIFEST_HEADER}\nzz Assemblies/a.dll\n");
        assert!(parse_manifest(&bad).is_err());
        let evil = format!("{MANIFEST_HEADER}\n{SAMPLE_A} ../escape.dll\n");
        assert!(parse_manifest(&evil).is_err());
        let empty = format!("{MANIFEST_HEADER}\n");
        assert!(parse_manifest(&empty).is_err());
    }

    #[test]
    fn hashes_like_blake2b_256() {
        let digest = blake2b_hex(b"abc");
        assert_eq!(
            digest,
            "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319"
        );
    }

    #[test]
    fn builds_request_body() {
        let entries = parse_manifest(&sample_manifest()).unwrap();
        let body = build_request_body(&entries);
        assert_eq!(body.len(), 8);
        assert_eq!(&body[..4], &0i32.to_le_bytes());
        assert_eq!(&body[4..], &1i32.to_le_bytes());
    }

    #[test]
    fn deduplicates_by_hash() {
        let dup =
            format!("{MANIFEST_HEADER}\n{SAMPLE_A} a.txt\n{SAMPLE_B} b.txt\n{SAMPLE_A} c.txt\n");
        let entries = parse_manifest(&dup).unwrap();
        let unique = unique_entries(&entries);
        assert_eq!(unique.len(), 2);
        assert_eq!(unique[0].index, 0);
        assert_eq!(unique[1].index, 1);
    }

    #[test]
    fn sanitizes_dir_names() {
        assert_eq!(sanitize_dir_name(" forks/x "), "forks_x");
        assert_eq!(sanitize_dir_name("///"), "___");
        assert_eq!(sanitize_dir_name("  "), "content");
    }

    #[test]
    fn decodes_precompressed_stream() {
        let file_a = b"hello assembly";
        let file_b = b"font data".to_vec();
        let compressed = zstd::stream::encode_all(&file_b[..], 3).unwrap();
        let mut stream = Vec::new();
        stream.extend_from_slice(&1i32.to_le_bytes());
        stream.extend_from_slice(&(file_a.len() as i32).to_le_bytes());
        stream.extend_from_slice(&(0i32).to_le_bytes());
        stream.extend_from_slice(file_a);
        stream.extend_from_slice(&(file_b.len() as i32).to_le_bytes());
        stream.extend_from_slice(&(compressed.len() as i32).to_le_bytes());
        stream.extend_from_slice(&compressed);

        let mut cursor = &stream[..];
        let mut flags = [0u8; 4];
        cursor.read_exact(&mut flags).unwrap();
        assert_eq!(i32::from_le_bytes(flags), 1);

        let mut length = [0u8; 4];
        cursor.read_exact(&mut length).unwrap();
        let mut compressed_length = [0u8; 4];
        cursor.read_exact(&mut compressed_length).unwrap();
        assert_eq!(i32::from_le_bytes(compressed_length), 0);
        let mut data = vec![0u8; i32::from_le_bytes(length) as usize];
        cursor.read_exact(&mut data).unwrap();
        assert_eq!(data, file_a);

        cursor.read_exact(&mut length).unwrap();
        cursor.read_exact(&mut compressed_length).unwrap();
        let mut packed = vec![0u8; i32::from_le_bytes(compressed_length) as usize];
        cursor.read_exact(&mut packed).unwrap();
        assert_eq!(packed, compressed);
        let mut restored = Vec::new();
        zstd::stream::Decoder::new(&packed[..])
            .unwrap()
            .read_to_end(&mut restored)
            .unwrap();
        assert_eq!(restored, file_b);
        assert!(cursor.is_empty());
    }

    #[test]
    fn overlay_zip_roundtrip() {
        let dir = std::env::temp_dir().join(format!("illusio-overlay-{}", std::process::id()));
        let blobs = dir.join("blobs");
        fs::create_dir_all(&blobs).unwrap();
        let body = b"client dll content".to_vec();
        let hash = blake2b_hex(&body);
        write_blob_cache(&blobs, &hash, &body).unwrap();
        let manifest = format!("{MANIFEST_HEADER}\n{hash} Assemblies/Content.Client.dll\n");
        let entries = parse_manifest(&manifest).unwrap();
        let target = dir.join("content.zip");
        let mut total = 0;
        assemble_overlay_zip(&entries, &blobs, &target, |value| total = value).unwrap();
        assert!(total > 0);
        let file = fs::File::open(&target).unwrap();
        let mut archive = zip::ZipArchive::new(file).unwrap();
        let mut entry = archive.by_name("Assemblies/Content.Client.dll").unwrap();
        let mut out = Vec::new();
        entry.read_to_end(&mut out).unwrap();
        assert_eq!(out, body);
        fs::remove_dir_all(&dir).ok();
    }
}

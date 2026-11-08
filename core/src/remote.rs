use serde::{Deserialize, Serialize};
use std::time::Duration;

pub const LAUNCHER_INFO_URL: &str = "https://launcher-data.cdn.spacestation14.com/info.json";

#[derive(Debug, Clone, Default, Serialize)]
pub struct LauncherUpdateCheck {
    #[serde(rename = "blocked")]
    pub blocked: bool,
    #[serde(rename = "minVersion")]
    pub min_version: String,
    #[serde(rename = "reason")]
    pub reason: String,
}

#[derive(Debug, Deserialize)]
struct RemoteLauncherInfo {
    #[serde(default, rename = "minVersion")]
    min_version: String,
    #[serde(default, rename = "blockedVersions")]
    blocked_versions: Vec<String>,
}

fn version_parts(value: &str) -> Vec<u64> {
    value
        .trim()
        .trim_start_matches('v')
        .split('.')
        .map(|part| {
            part.chars()
                .take_while(|c| c.is_ascii_digit())
                .collect::<String>()
                .parse()
                .unwrap_or(0)
        })
        .collect()
}

pub fn version_is_below(current: &str, minimum: &str) -> bool {
    let minimum = minimum.trim();
    if minimum.is_empty() {
        return false;
    }
    let left = version_parts(current);
    let right = version_parts(minimum);
    let width = left.len().max(right.len());
    for index in 0..width {
        let a = left.get(index).copied().unwrap_or(0);
        let b = right.get(index).copied().unwrap_or(0);
        if a != b {
            return a < b;
        }
    }
    false
}

pub fn version_is_blocked(current: &str, blocked: &[String]) -> bool {
    let current = current.trim();
    blocked
        .iter()
        .any(|version| version.trim() == current && !current.is_empty())
}

pub fn fetch_update_check(current_version: &str) -> Result<LauncherUpdateCheck, String> {
    let client = crate::http::with_route(
        reqwest::blocking::Client::builder(),
        crate::http::Route::Updates,
    )
    .timeout(Duration::from_secs(10))
    .build()
    .map_err(|error| error.to_string())?;
    let response = client
        .get(LAUNCHER_INFO_URL)
        .send()
        .map_err(|error| error.to_string())?;
    let response = response
        .error_for_status()
        .map_err(|error| format!("info.json ответил с ошибкой: {error}"))?;
    let info: RemoteLauncherInfo = response
        .json()
        .map_err(|error| format!("не удалось разобрать info.json: {error}"))?;
    let min_version = info.min_version.trim().to_string();
    if version_is_blocked(current_version, &info.blocked_versions) {
        return Ok(LauncherUpdateCheck {
            blocked: true,
            reason: "версия заблокирована сервером".into(),
            min_version,
        });
    }
    if version_is_below(current_version, &min_version) {
        return Ok(LauncherUpdateCheck {
            blocked: true,
            reason: format!("требуется версия не ниже {min_version}"),
            min_version,
        });
    }
    Ok(LauncherUpdateCheck {
        blocked: false,
        min_version,
        reason: String::new(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compares_versions() {
        assert!(version_is_below("0.4.0", "0.5.0"));
        assert!(version_is_below("0.4.0", "0.4.1"));
        assert!(version_is_below("0.4", "0.4.1"));
        assert!(version_is_below("v0.3.0", "0.4.0"));
        assert!(!version_is_below("0.5.0", "0.4.9"));
        assert!(!version_is_below("0.4.0", "0.4.0"));
        assert!(!version_is_below("0.4.0", ""));
        assert!(!version_is_below("1.0.0", "0.9.9"));
    }

    #[test]
    fn checks_blocked_versions() {
        let blocked = vec!["0.3.9".into(), "0.4.0".into()];
        assert!(version_is_blocked("0.4.0", &blocked));
        assert!(!version_is_blocked("0.4.1", &blocked));
        assert!(!version_is_blocked("", &["".into()]));
    }
}

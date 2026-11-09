use serde::Serialize;

#[derive(Debug, Clone, Default, Serialize)]
pub struct HealthReport {
    pub platform: String,
    #[serde(rename = "vcRedistInstalled", skip_serializing_if = "Option::is_none")]
    pub vc_redist_installed: Option<bool>,
    #[serde(rename = "vcRedistVersion", skip_serializing_if = "Option::is_none")]
    pub vc_redist_version: Option<String>,
    #[serde(rename = "wineInstalled", skip_serializing_if = "Option::is_none")]
    pub wine_installed: Option<bool>,
    #[serde(rename = "rosettaInstalled", skip_serializing_if = "Option::is_none")]
    pub rosetta_installed: Option<bool>,
}

pub fn report() -> HealthReport {
    if cfg!(windows) {
        let (installed, version) = check_vc_redist();
        return HealthReport {
            platform: "windows".into(),
            vc_redist_installed: Some(installed),
            vc_redist_version: version,
            ..HealthReport::default()
        };
    }
    if cfg!(target_os = "macos") {
        return HealthReport {
            platform: "macos".into(),
            rosetta_installed: Some(check_rosetta()),
            ..HealthReport::default()
        };
    }
    HealthReport {
        platform: "linux".into(),
        wine_installed: Some(check_wine()),
        ..HealthReport::default()
    }
}

pub fn parse_reg_version(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    let number: String = trimmed
        .chars()
        .skip_while(|c| !c.is_ascii_digit())
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .collect();
    let number = number.trim_matches('.').to_string();
    if number.is_empty() {
        None
    } else {
        Some(number)
    }
}

#[cfg(windows)]
fn check_vc_redist() -> (bool, Option<String>) {
    use std::os::windows::process::CommandExt;

    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    const KEYS: [&str; 2] = [
        r"SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64",
        r"SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64",
    ];
    for key in KEYS {
        let Ok(output) = std::process::Command::new("reg")
            .args(["query", key, "/v", "Version"])
            .creation_flags(CREATE_NO_WINDOW)
            .output()
        else {
            continue;
        };
        if !output.status.success() {
            continue;
        }
        let text = String::from_utf8_lossy(&output.stdout);
        for line in text.lines() {
            let Some((name, value)) = line.split_once("REG_SZ") else {
                continue;
            };
            if name.contains("Version") {
                return (true, parse_reg_version(value));
            }
        }
    }
    (false, None)
}

#[cfg(not(windows))]
fn check_vc_redist() -> (bool, Option<String>) {
    (false, None)
}

fn check_wine() -> bool {
    std::process::Command::new("wine")
        .arg("--version")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

fn check_rosetta() -> bool {
    Path::new("/usr/libexec/rosetta/oahd").exists()
        || Path::new("/Library/Apple/usr/libexec/oah/libRosettaRuntime").exists()
}

use std::path::Path;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_registry_versions() {
        assert_eq!(
            parse_reg_version("v14.38.33130 - checked"),
            Some("14.38.33130".to_string())
        );
        assert_eq!(
            parse_reg_version("14.40.33810.0"),
            Some("14.40.33810.0".to_string())
        );
        assert_eq!(parse_reg_version(""), None);
        assert_eq!(parse_reg_version("not-a-version"), None);
    }

    #[test]
    fn reports_platform_shape() {
        let health = report();
        if cfg!(windows) {
            assert_eq!(health.platform, "windows");
            assert!(health.vc_redist_installed.is_some());
            assert!(health.wine_installed.is_none());
        } else if cfg!(target_os = "macos") {
            assert_eq!(health.platform, "macos");
            assert!(health.rosetta_installed.is_some());
        } else {
            assert_eq!(health.platform, "linux");
            assert!(health.wine_installed.is_some());
        }
        let raw = serde_json::to_string(&health).unwrap();
        assert!(raw.contains("\"platform\""));
    }
}

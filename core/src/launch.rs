use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::{Command, Stdio};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct LaunchSpec {
    #[serde(default)]
    pub install_dir: String,
    #[serde(default)]
    pub args: Vec<String>,
}

pub fn client_path(install_dir: &str) -> PathBuf {
    let dir = PathBuf::from(install_dir);
    if cfg!(windows) {
        dir.join("Robust.Client.exe")
    } else {
        dir.join("Robust.Client")
    }
}

pub fn launch(spec: &LaunchSpec) -> Result<u32, String> {
    let path = client_path(&spec.install_dir);
    if !path.exists() {
        return Err(format!("клиент не найден: {}", path.display()));
    }
    let child = Command::new(&path)
        .args(&spec.args)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| error.to_string())?;
    Ok(child.id())
}

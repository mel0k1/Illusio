use illusio::config::{load_from, save_to, Config};
use std::env;
use std::fs;
use std::path::PathBuf;

#[test]
fn config_roundtrip() {
    let dir = env::temp_dir().join(format!("illusio-test-{}", std::process::id()));
    let path = dir.join("config.json");
    let mut config = Config::default();
    config.install_dir = "/opt/ss14".into();
    config.launch_args = vec!["--profile".into(), "server".into()];
    config.last_server = "example.com".into();
    save_to(&path, &config).expect("save failed");
    let loaded = load_from(&path).expect("load failed");
    assert_eq!(loaded.install_dir, "/opt/ss14");
    assert_eq!(loaded.launch_args.len(), 2);
    assert_eq!(loaded.last_server, "example.com");
    fs::remove_dir_all(dir).ok();
}

#[test]
fn missing_config_returns_default() {
    let path = PathBuf::from(env::temp_dir().join("illusio-missing-config.json"));
    let loaded = load_from(&path).expect("load failed");
    assert_eq!(loaded.install_dir, "");
    assert!(loaded.launch_args.is_empty());
}

use illusio::auth::LoginInfo;
use illusio::config::{load_from, save_to, Config, FavoriteEntry, PrivacyAccept};
use std::env;
use std::fs;

#[test]
fn config_roundtrip() {
    let dir = env::temp_dir().join(format!("illusio-test-{}", std::process::id()));
    let path = dir.join("config.json");
    let config = Config {
        install_dir: "/opt/ss14".into(),
        launch_args: vec!["--profile".into(), "server".into()],
        last_server: "example.com".into(),
        login: None,
        favorites: vec![FavoriteEntry {
            name: "Wormix".into(),
            url: "ss14://wormix14.site".into(),
            raised: 7,
        }],
        accounts: vec![LoginInfo::default()],
        theme: "dark".into(),
        hide_empty: true,
        hide_full: false,
        fullscreen: false,
        vsync: true,
        mods_enabled: vec!["pack_a.zip".into()],
        hubs: vec!["https://hub.example.com/".into()],
        guest_username: "Гость".into(),
        username_override: String::new(),
        engine_override: String::new(),
        client_logs: true,
        filter_tags: vec!["lang:ru".into()],
        filter_min_players: 0,
        filter_max_players: 0,
        accepted_privacy: vec![PrivacyAccept {
            identifier: "corvax".into(),
            version: "1".into(),
        }],
    };
    save_to(&path, &config).expect("save failed");
    let loaded = load_from(&path).expect("load failed");
    assert_eq!(loaded.install_dir, "/opt/ss14");
    assert_eq!(loaded.launch_args.len(), 2);
    assert_eq!(loaded.last_server, "example.com");
    assert_eq!(loaded.favorites.len(), 1);
    assert_eq!(loaded.favorites[0].url, "ss14://wormix14.site");
    assert_eq!(loaded.favorites[0].raised, 7);
    assert_eq!(loaded.accounts.len(), 1);
    assert_eq!(loaded.theme, "dark");
    assert!(loaded.hide_empty);
    assert!(loaded.vsync);
    assert_eq!(loaded.mods_enabled, vec!["pack_a.zip".to_string()]);
    assert_eq!(loaded.hubs, vec!["https://hub.example.com/".to_string()]);
    assert_eq!(loaded.guest_username, "Гость");
    assert!(loaded.client_logs);
    assert_eq!(loaded.filter_tags, vec!["lang:ru".to_string()]);
    assert_eq!(loaded.accepted_privacy.len(), 1);
    fs::remove_dir_all(dir).ok();
}

#[test]
fn missing_config_returns_default() {
    let path = env::temp_dir().join("illusio-missing-config.json");
    let loaded = load_from(&path).expect("load failed");
    assert_eq!(loaded.install_dir, "");
    assert!(loaded.launch_args.is_empty());
    assert!(loaded.login.is_none());
    assert!(loaded.favorites.is_empty());
    assert!(loaded.accounts.is_empty());
    assert_eq!(loaded.theme, "");
    assert!(!loaded.hide_empty);
}

#[test]
fn legacy_config_still_loads() {
    let dir = env::temp_dir().join(format!("illusio-legacy-{}", std::process::id()));
    let path = dir.join("config.json");
    fs::create_dir_all(&dir).unwrap();
    fs::write(
        &path,
        r#"{"install_dir":"/opt/ss14","launch_args":["--profile"],"last_server":"a.b"}"#,
    )
    .unwrap();
    let loaded = load_from(&path).expect("load failed");
    assert_eq!(loaded.install_dir, "/opt/ss14");
    assert!(loaded.favorites.is_empty());
    assert!(loaded.accounts.is_empty());
    fs::remove_dir_all(dir).ok();
}

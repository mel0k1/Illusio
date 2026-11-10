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
        language: "ru".into(),
        proxy_enabled: false,
        proxy_updates: false,
        proxy_region_bypass: false,
        proxy_host: String::new(),
        proxy_port: 0,
        proxy_username: String::new(),
        proxy_password: String::new(),
        proxy_profiles: Vec::new(),
        proxy_selected: String::new(),
        proxy_udp_relay: false,
        proxy_apply_to_game: false,
        dll_mods_enabled: Vec::new(),
        subverter_enabled: vec!["game_mod.dll".into()],
        res_packs_enabled: vec!["HiTech".into()],
        dump_resources: true,
        blob_keep_days: 7,
        bundle_keep: 10,
        engine_keep: 2,
        auto_update: false,
        prefetch_favorites: false,
        patch_hwid: false,
        patch_rpc: false,
        patch_jam_dials: false,
        patch_blackhole: false,
        skip_privacy: true,
        throw_patch_fail: false,
        no_autologin: true,
        patch_flyi: false,
        ps_debug: true,
        hide_level: 2,
        hwid_mode: "fixed".into(),
        hwid_value: "aabb".into(),
        hwid_optout: true,
        dynamic_pgo: true,
        backports: true,
        backports_no_any: false,
        rpc_fake: false,
        rpc_fake_name: "Illusio".into(),
        proxy_guard_launch: true,
        dock_side: "bottom".into(),
        corners: "normal".into(),
        font: "default".into(),
        custom_color: 0,
        patchless: false,
        stealth_registries: false,
        admin_guid: false,
        admin_guid_value: String::new(),
        mod_logs: false,
        filter_hubs: Vec::new(),
        update_prerelease: false,
        card_map: true,
        card_preset: true,
        card_round: true,
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
    assert_eq!(loaded.subverter_enabled, vec!["game_mod.dll".to_string()]);
    assert_eq!(loaded.res_packs_enabled, vec!["HiTech".to_string()]);
    assert!(loaded.dump_resources);
    assert_eq!(loaded.hubs, vec!["https://hub.example.com/".to_string()]);
    assert_eq!(loaded.guest_username, "Гость");
    assert!(loaded.client_logs);
    assert_eq!(loaded.filter_tags, vec!["lang:ru".to_string()]);
    assert_eq!(loaded.accepted_privacy.len(), 1);
    assert!(loaded.skip_privacy);
    assert!(!loaded.throw_patch_fail);
    assert!(loaded.no_autologin);
    assert!(!loaded.patch_flyi);
    assert!(loaded.ps_debug);
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

use illusio::status::{status_url, ServerStatus};

#[test]
fn builds_status_url() {
    assert_eq!(status_url("example.com"), "example.com/status");
    assert_eq!(status_url("example.com/"), "example.com/status");
}

#[test]
fn parses_full_status_payload() {
    let raw = r#"{
        "name": "Тестовый сервер",
        "statusMessage": "<p>Добро пожаловать</p>",
        "tags": ["roleplay", "ru"],
        "softMaxPlayers": 80,
        "playerCount": 42
    }"#;
    let status: ServerStatus = serde_json::from_str(raw).expect("parse failed");
    assert_eq!(status.name, "Тестовый сервер");
    assert_eq!(status.tags.len(), 2);
    assert_eq!(status.soft_max_players, 80);
    assert_eq!(status.player_count, 42);
}

#[test]
fn tolerates_missing_fields() {
    let status: ServerStatus = serde_json::from_str("{}").expect("parse failed");
    assert_eq!(status.name, "");
    assert_eq!(status.player_count, 0);
    assert!(status.tags.is_empty());
}
